import 'dart:async';

import 'package:shuttle/core/utils/current_and_changes.dart';
import 'package:shuttle/features/identity/data/data_sources/identity_local_data_source.dart';
import 'package:shuttle/features/identity/domain/entities/device_identity.dart';
import 'package:shuttle/features/identity/domain/repositories/identity_repository.dart';

class IdentityRepositoryImpl implements IdentityRepository {
  IdentityRepositoryImpl(this._dataSource) : _identity = _dataSource.read();

  final IdentityLocalDataSource _dataSource;
  final StreamController<DeviceIdentity> _controller =
      StreamController<DeviceIdentity>.broadcast();

  DeviceIdentity _identity;

  @override
  DeviceIdentity get current => _identity;

  @override
  Stream<DeviceIdentity> watch() =>
      currentAndChanges(() => _identity, _controller.stream);

  @override
  Future<DeviceIdentity> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _identity.name) return _identity;

    _identity = _identity.copyWith(name: trimmed);
    _controller.add(_identity);
    await _dataSource.write(_identity);
    return _identity;
  }

  Future<void> dispose() => _controller.close();
}
