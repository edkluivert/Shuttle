import 'package:equatable/equatable.dart';
import 'package:shuttle/core/utils/formatters.dart';

/// A file a peer is offering. Addressed by position — that is what the
/// download URL uses.
class RemoteFile extends Equatable {
  const RemoteFile({required this.name, required this.size});

  final String name;
  final int size;

  String get readableSize => formatBytes(size);

  @override
  List<Object?> get props => [name, size];
}
