import 'dart:io';

import 'package:shuttle/core/error/result.dart';
import 'package:shuttle/features/transfer/domain/entities/remote_file.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/features/transfer/domain/repositories/transfer_repository.dart';

class TransferUseCase {
  const TransferUseCase(this._repository);

  final TransferRepository _repository;

  Future<Result<List<RemoteFile>>> listFiles(String host, int port) =>
      _repository.listFiles(host, port);

  Future<int> download({
    required String host,
    required int port,
    required List<({int index, RemoteFile file})> files,
    void Function(TransferProgress progress)? onProgress,
  }) => _repository.download(
    host: host,
    port: port,
    files: files,
    onProgress: onProgress,
  );

  Future<int> send({
    required String host,
    required int port,
    required List<File> files,
    void Function(TransferProgress progress)? onProgress,
  }) => _repository.send(
    host: host,
    port: port,
    files: files,
    onProgress: onProgress,
  );

  void cancel() => _repository.cancel();

  Future<List<File>> inboxContents() => _repository.inboxContents();

  Directory inboxDirectory() => _repository.inboxDirectory;
}
