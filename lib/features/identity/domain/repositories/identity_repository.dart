import 'package:shuttle/features/identity/domain/entities/device_identity.dart';

abstract interface class IdentityRepository {
  DeviceIdentity get current;

  Stream<DeviceIdentity> watch();

  Future<DeviceIdentity> rename(String name);
}
