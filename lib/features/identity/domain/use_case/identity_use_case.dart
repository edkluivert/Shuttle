import 'package:shuttle/features/identity/domain/entities/device_identity.dart';
import 'package:shuttle/features/identity/domain/repositories/identity_repository.dart';

class IdentityUseCase {
  const IdentityUseCase(this._repository);

  final IdentityRepository _repository;

  DeviceIdentity current() => _repository.current;

  Stream<DeviceIdentity> watch() => _repository.watch();

  Future<DeviceIdentity> rename(String name) => _repository.rename(name);
}
