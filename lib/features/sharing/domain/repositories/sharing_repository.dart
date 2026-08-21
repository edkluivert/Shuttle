import 'dart:io';

import 'package:shuttle/features/sharing/domain/entities/server_status.dart';

/// The device's side of a transfer: what it offers, and the server offering
/// it.
abstract interface class SharingRepository {
  Stream<ServerStatus> watch();

  ServerStatus get status;

  Future<void> start();

  Future<void> stop();

  void share(Iterable<File> files);

  void unshareAt(int index);

  void unshareAll();
}
