import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/identity/domain/entities/device_identity.dart';
import 'package:shuttle/features/identity/domain/use_case/identity_use_case.dart';

class IdentityState extends Equatable {
  const IdentityState({required this.identity});

  final DeviceIdentity identity;

  @override
  List<Object?> get props => [identity];
}

/// Created by the shell that shows the device name, not held app-wide: the
/// name itself lives in the repository, so this can come and go freely.
class IdentityCubit extends Cubit<IdentityState> {
  IdentityCubit(this._useCase)
    : super(IdentityState(identity: _useCase.current())) {
    _subscription = _useCase.watch().listen((identity) {
      if (!isClosed) emit(IdentityState(identity: identity));
    });
  }

  final IdentityUseCase _useCase;
  StreamSubscription<DeviceIdentity>? _subscription;

  Future<void> rename(String name) => _useCase.rename(name);

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
