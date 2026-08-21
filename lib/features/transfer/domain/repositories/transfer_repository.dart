import 'dart:io';

import 'package:shuttle/core/error/result.dart';
import 'package:shuttle/features/transfer/domain/entities/remote_file.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';

abstract interface class TransferRepository {
  /// What a peer is offering. An empty list means it is sharing nothing; a
  /// failure means it could not be reached — the screen says something
  /// different for each.
  Future<Result<List<RemoteFile>>> listFiles(String host, int port);

  /// Downloads files one after another, reporting progress as it goes.
  /// Returns how many landed.
  Future<int> download({
    required String host,
    required int port,
    required List<({int index, RemoteFile file})> files,
    void Function(TransferProgress progress)? onProgress,
  });

  /// Pushes local files into a peer's inbox, one after another. Returns how
  /// many arrived.
  Future<int> send({
    required String host,
    required int port,
    required List<File> files,
    void Function(TransferProgress progress)? onProgress,
  });

  void cancel();

  Future<List<File>> inboxContents();

  Directory get inboxDirectory;
}
