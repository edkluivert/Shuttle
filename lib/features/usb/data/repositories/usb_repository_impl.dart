import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:shuttle/features/usb/domain/repositories/usb_repository.dart';
import 'package:path/path.dart' as p;

class UsbRepositoryImpl implements UsbRepository {
  UsbRepositoryImpl({
    required List<UsbBackend> backends,
    required Directory inbox,
    required HistoryUseCase history,
  }) : _backends = backends,
       _inbox = inbox,
       _history = history;

  final List<UsbBackend> _backends;
  final Directory _inbox;
  final HistoryUseCase _history;

  final TransferRate _rate = TransferRate();
  UsbBackend? _active;

  @override
  List<UsbBackend> get backends => List.unmodifiable(_backends);

  @override
  UsbBackend? get activeBackend => _active;

  @override
  Future<Map<String, bool>> probeBackends() async {
    final availability = <String, bool>{};
    for (final backend in _backends) {
      availability[backend.name] = await backend.isAvailable();
    }
    // Worth logging: when this is false on a machine where the tool works
    // from a terminal, the answer is almost always that the app cannot reach
    // the binary, not that it is missing.
    debugPrint('USB backends: $availability');
    return availability;
  }

  @override
  Future<UsbDevice?> scan({String? preferredBackend}) async {
    // Automatic means "the ones that can answer in a moment". A backend that
    // has to read the whole phone before it can say whether one is connected
    // is only ever run because the user asked for it by name.
    final candidates = preferredBackend == null
        ? _backends.where((b) => b.scansQuickly)
        : _backends.where((b) => b.name == preferredBackend);

    for (final backend in candidates) {
      if (!await backend.isAvailable()) continue;

      final devices = await backend.devices();
      if (devices.isEmpty) continue;

      _active = backend;
      debugPrint('USB: ${devices.first.label} via ${backend.name}');
      return devices.first;
    }

    _active = null;
    return null;
  }

  @override
  Future<List<UsbEntry>> list(UsbDevice device, String path) async {
    final backend = _active;
    if (backend == null) return const [];
    return backend.list(device, path);
  }

  /// Sequential on purpose: the cable is the bottleneck, so two copies at
  /// once finish no sooner and turn one honest progress bar into two
  /// misleading ones.
  @override
  Future<int> pull({
    required UsbDevice device,
    required List<UsbEntry> entries,
    void Function(TransferProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final backend = _active;
    if (backend == null) return 0;

    var saved = 0;
    for (var i = 0; i < entries.length; i++) {
      if (isCancelled?.call() ?? false) break;

      final entry = entries[i];
      _rate.reset();

      final path = await backend.pull(
        device,
        entry,
        _inbox,
        onProgress: (received, total) {
          _rate.update(received, DateTime.now());
          onProgress?.call(
            TransferProgress(
              name: entry.name,
              received: received,
              total: total,
              fileIndex: i + 1,
              fileCount: entries.length,
              bytesPerSecond: _rate.bytesPerSecond,
            ),
          );
        },
      );

      if (path != null) {
        saved++;
        await _history.record(
          name: entry.name,
          bytes: entry.size > 0 ? entry.size : 0,
          peer: device.label,
          incoming: true,
          way: TransferWay.usb,
          path: path,
        );
      }
    }
    return saved;
  }

  @override
  Future<bool> push({
    required UsbDevice device,
    required File file,
    required String remoteDirectory,
  }) async {
    final backend = _active;
    if (backend == null) return false;

    final ok = await backend.push(device, file, remoteDirectory);
    if (ok) {
      await _history.record(
        name: p.basename(file.path),
        bytes: file.existsSync() ? file.lengthSync() : 0,
        peer: device.label,
        incoming: false,
        way: TransferWay.usb,
        path: file.path,
      );
    }
    return ok;
  }
}
