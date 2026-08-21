import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:shuttle/core/utils/formatters.dart';
import 'package:path/path.dart' as p;

/// One file being offered to the network.
class SharedFile extends Equatable {
  const SharedFile({required this.name, required this.size, this.path});

  factory SharedFile.fromFile(File file) => SharedFile(
    name: p.basename(file.path),
    size: file.existsSync() ? file.lengthSync() : 0,
    path: file.path,
  );

  final String name;
  final int size;

  /// Only set for files this device is sharing; a peer's files are remote.
  final String? path;

  String get readableSize => formatBytes(size);

  @override
  List<Object?> get props => [name, size, path];
}
