import 'dart:async';

import 'package:shuttle/features/discovery/data/data_sources/mdns_data_source.dart';
import 'package:shuttle/features/discovery/domain/entities/peer.dart';
import 'package:shuttle/features/discovery/domain/repositories/discovery_repository.dart';

class DiscoveryRepositoryImpl implements DiscoveryRepository {
  DiscoveryRepositoryImpl(this._dataSource);

  final MdnsDataSource _dataSource;

  @override
  Object? get lastError => _dataSource.lastError;

  @override
  Stream<List<Peer>> watchPeers() => _dataSource.peers;

  @override
  Future<void> advertise({
    required String deviceId,
    required String deviceName,
    required int port,
  }) => _dataSource.advertise(
    deviceId: deviceId,
    deviceName: deviceName,
    port: port,
  );

  @override
  Future<void> startSearching() => _dataSource.startSearching();

  @override
  Future<void> refresh() => _dataSource.refresh();

  @override
  Future<void> stop() => _dataSource.stop();
}
