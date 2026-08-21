import 'package:equatable/equatable.dart';
import 'package:shuttle/features/sharing/domain/entities/shared_file.dart';

/// What the local server is doing right now.
class ServerStatus extends Equatable {
  const ServerStatus({
    this.isRunning = false,
    this.port,
    this.addresses = const [],
    this.files = const [],
  });

  final bool isRunning;
  final int? port;

  /// One per network this device is on. More than one usually means Wi-Fi
  /// plus a USB tether, and only one of them is the one the other device is
  /// on — so all of them are offered rather than a guess.
  final List<String> addresses;

  final List<SharedFile> files;

  /// `http://192.168.1.5:53317` — what you type on the other device.
  String? get primaryUrl {
    if (addresses.isEmpty || port == null) return null;
    return 'http://${addresses.first}:$port';
  }

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  ServerStatus copyWith({
    bool? isRunning,
    int? port,
    List<String>? addresses,
    List<SharedFile>? files,
  }) => ServerStatus(
    isRunning: isRunning ?? this.isRunning,
    port: port ?? this.port,
    addresses: addresses ?? this.addresses,
    files: files ?? this.files,
  );

  @override
  List<Object?> get props => [isRunning, port, addresses, files];
}
