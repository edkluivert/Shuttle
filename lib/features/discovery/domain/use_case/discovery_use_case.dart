import 'package:shuttle/features/discovery/domain/entities/peer.dart';
import 'package:shuttle/features/discovery/domain/repositories/discovery_repository.dart';

class DiscoveryUseCase {
  const DiscoveryUseCase(this._repository);

  final DiscoveryRepository _repository;

  Stream<List<Peer>> watchPeers() => _repository.watchPeers();

  Future<void> advertise({
    required String deviceId,
    required String deviceName,
    required int port,
  }) => _repository.advertise(
    deviceId: deviceId,
    deviceName: deviceName,
    port: port,
  );

  Future<void> startSearching() => _repository.startSearching();

  Future<void> refresh() => _repository.refresh();

  Future<void> stop() => _repository.stop();

  Object? lastError() => _repository.lastError;
}
