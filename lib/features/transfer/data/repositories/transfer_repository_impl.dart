import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/core/error/failure.dart';
import 'package:shuttle/core/error/result.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/transfer/data/data_sources/http_transfer_data_source.dart';
import 'package:shuttle/features/transfer/domain/entities/remote_file.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:path/path.dart' as p;

class TransferRepositoryImpl implements TransferRepository {
  TransferRepositoryImpl({
    required HttpTransferDataSource dataSource,
    required Directory inbox,
    required HistoryUseCase history,
  }) : _dataSource = dataSource,
       _inbox = inbox,
       _history = history;

  final HttpTransferDataSource _dataSource;
  final Directory _inbox;
  final HistoryUseCase _history;

  final TransferRate _rate = TransferRate();
  bool _cancelRequested = false;

  @override
  Directory get inboxDirectory => _inbox;

  @override
  Future<Result<List<RemoteFile>>> listFiles(String host, int port) async {
    final raw = await _dataSource.listFiles(host, port);
    if (raw == null) return const Err(NetworkFailure());

    return Ok(
      raw
          .map(
            (json) => RemoteFile(
              name: json['name']?.toString() ?? 'file',
              size: (json['size'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(growable: false),
    );
  }

  /// Sequential rather than parallel: the files share one link, so running
  /// them at once just makes every bar slower and none of them meaningful.
  @override
  Future<int> download({
    required String host,
    required int port,
    required List<({int index, RemoteFile file})> files,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    _cancelRequested = false;
    var saved = 0;

    for (var i = 0; i < files.length; i++) {
      if (_cancelRequested) break;

      final entry = files[i];
      _rate.reset();

      // Written under a temporary name and moved on success: a failed or
      // cancelled transfer must not leave something that looks finished.
      final savePath = _uniquePath(entry.file.name);
      final tempPath = '$savePath.part';

      try {
        await _inbox.create(recursive: true);
        await _dataSource.download(
          host: host,
          port: port,
          index: entry.index,
          savePath: tempPath,
          onProgress: (received, total) {
            _rate.update(received, DateTime.now());
            onProgress?.call(
              TransferProgress(
                name: entry.file.name,
                received: received,
                total: total > 0 ? total : entry.file.size,
                fileIndex: i + 1,
                fileCount: files.length,
                bytesPerSecond: _rate.bytesPerSecond,
              ),
            );
          },
        );

        await File(tempPath).rename(savePath);
        saved++;
        await _history.record(
          name: entry.file.name,
          bytes: File(savePath).lengthSync(),
          peer: host,
          incoming: true,
          way: TransferWay.network,
          path: savePath,
        );
      } catch (e) {
        if (!HttpTransferDataSource.isCancellation(e)) {
          debugPrint('Download failed: $e');
        }
        await _deleteQuietly(tempPath);
      }
    }

    _cancelRequested = false;
    return saved;
  }

  /// Sequential, and for the same reason downloads are: one link, one honest
  /// progress bar.
  @override
  Future<int> send({
    required String host,
    required int port,
    required List<File> files,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    _cancelRequested = false;
    var sent = 0;

    for (var i = 0; i < files.length; i++) {
      if (_cancelRequested) break;

      final file = files[i];
      final name = p.basename(file.path);
      _rate.reset();

      try {
        await _dataSource.upload(
          host: host,
          port: port,
          file: file,
          onProgress: (uploaded, total) {
            _rate.update(uploaded, DateTime.now());
            onProgress?.call(
              TransferProgress(
                name: name,
                received: uploaded,
                total: total,
                fileIndex: i + 1,
                fileCount: files.length,
                bytesPerSecond: _rate.bytesPerSecond,
              ),
            );
          },
        );

        sent++;
        await _history.record(
          name: name,
          bytes: file.existsSync() ? file.lengthSync() : 0,
          peer: host,
          incoming: false,
          way: TransferWay.network,
          // The original, still sitting wherever the user picked it from.
          path: file.path,
        );
      } catch (e) {
        // Nothing to clean up on this side — a failed push leaves the partial
        // file on the *receiver*, which deletes it itself.
        if (!HttpTransferDataSource.isCancellation(e)) {
          debugPrint('Send failed: $e');
        }
      }
    }

    _cancelRequested = false;
    return sent;
  }

  @override
  void cancel() {
    _cancelRequested = true;
    _dataSource.cancel();
  }

  @override
  Future<List<File>> inboxContents() async {
    try {
      if (!_inbox.existsSync()) return const [];
      final entries = _inbox
          .listSync()
          .whereType<File>()
          // Half-finished downloads are not files the user has.
          .where((f) => !f.path.endsWith('.part'))
          .toList();
      entries.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      return entries;
    } catch (e) {
      debugPrint('Could not read inbox: $e');
      return const [];
    }
  }

  String _uniquePath(String name) {
    var candidate = p.join(_inbox.path, name);
    if (!File(candidate).existsSync()) return candidate;

    final stem = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 1; i < 1000; i++) {
      candidate = p.join(_inbox.path, '$stem ($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    return candidate;
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  void dispose() => _dataSource.dispose();
}
