import 'dart:io';

import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:shuttle/features/usb/domain/repositories/usb_repository.dart';

class UsbUseCase {
  const UsbUseCase(this._repository);

  final UsbRepository _repository;

  Future<Map<String, bool>> probeBackends() => _repository.probeBackends();

  List<UsbBackend> backends() => _repository.backends;

  UsbBackend? activeBackend() => _repository.activeBackend;

  Future<UsbDevice?> scan({String? preferredBackend}) =>
      _repository.scan(preferredBackend: preferredBackend);

  Future<List<UsbEntry>> list(UsbDevice device, String path) =>
      _repository.list(device, path);

  Future<int> pull({
    required UsbDevice device,
    required List<UsbEntry> entries,
    void Function(TransferProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) => _repository.pull(
    device: device,
    entries: entries,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  Future<bool> push({
    required UsbDevice device,
    required File file,
    required String remoteDirectory,
  }) => _repository.push(
    device: device,
    file: file,
    remoteDirectory: remoteDirectory,
  );
}
