import 'package:shuttle/features/discovery/domain/entities/peer.dart';

abstract interface class DiscoveryRepository {
  Stream<List<Peer>> watchPeers();

  /// Announce this device so others can find it.
  Future<void> advertise({
    required String deviceId,
    required String deviceName,
    required int port,
  });

  Future<void> startSearching();

  /// Drop and restart the browse — the pull-to-refresh of mDNS, for a device
  /// that joined after the search began.
  Future<void> refresh();

  Future<void> stop();

  Object? get lastError;
}
