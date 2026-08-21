import 'dart:io';

import 'package:shuttle/features/sharing/domain/entities/server_status.dart';
import 'package:shuttle/features/sharing/domain/repositories/sharing_repository.dart';

class SharingUseCase {
  const SharingUseCase(this._repository);

  final SharingRepository _repository;

  Stream<ServerStatus> watch() => _repository.watch();

  ServerStatus status() => _repository.status;

  Future<void> start() => _repository.start();

  Future<void> stop() => _repository.stop();

  void share(Iterable<File> files) => _repository.share(files);

  void unshareAt(int index) => _repository.unshareAt(index);

  void unshareAll() => _repository.unshareAll();
}
