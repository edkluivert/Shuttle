import 'package:equatable/equatable.dart';

/// One entry in a phone's storage, as seen over a USB cable.
class UsbEntry extends Equatable {
  const UsbEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;

  @override
  List<Object?> get props => [name, path, isDirectory, size];
}

/// A phone reachable over the cable.
class UsbDevice extends Equatable {
  const UsbDevice({
    required this.id,
    required this.label,
    required this.rootPath,
  });

  final String id;
  final String label;

  /// Where browsing starts — `/sdcard` on Android.
  final String rootPath;

  @override
  List<Object?> get props => [id, label, rootPath];
}
