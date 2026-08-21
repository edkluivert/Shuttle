import 'package:equatable/equatable.dart';

/// Who this device says it is on the network.
class DeviceIdentity extends Equatable {
  const DeviceIdentity({required this.id, required this.name});

  /// Stable across renames and restarts. Self-filtering during discovery
  /// matches on this — matching on the display name meant two devices that
  /// happened to share one hid each other.
  final String id;

  final String name;

  DeviceIdentity copyWith({String? name}) =>
      DeviceIdentity(id: id, name: name ?? this.name);

  @override
  List<Object?> get props => [id, name];
}
