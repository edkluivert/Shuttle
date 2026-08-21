import 'dart:io';

import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';

/// Browsing a phone that is plugged in, rather than one on the network.
abstract interface class UsbRepository {
  /// Which ways of connecting are usable on this machine. Cheap — it only
  /// checks the helper binaries, never the device.
  Future<Map<String, bool>> probeBackends();

  List<UsbBackend> get backends;

  /// Finds a device using [preferredBackend], or the first that works.
  Future<UsbDevice?> scan({String? preferredBackend});

  UsbBackend? get activeBackend;

  Future<List<UsbEntry>> list(UsbDevice device, String path);

  /// Copies files off the phone into the inbox. Returns how many landed.
  Future<int> pull({
    required UsbDevice device,
    required List<UsbEntry> entries,
    void Function(TransferProgress progress)? onProgress,
    bool Function()? isCancelled,
  });

  Future<bool> push({
    required UsbDevice device,
    required File file,
    required String remoteDirectory,
  });
}
