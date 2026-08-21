import 'package:equatable/equatable.dart';

/// Another device running this app, found on the network.
class Peer extends Equatable {
  const Peer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });

  final String id;
  final String name;

  /// Null until the service resolves — a peer with no address cannot be
  /// dialled, and the UI shows it as still resolving rather than offering a
  /// tap that would fail.
  final String? host;
  final int? port;

  bool get isReachable => host != null && port != null;

  @override
  List<Object?> get props => [id, name, host, port];
}
