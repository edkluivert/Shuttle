import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';
import 'package:shuttle/features/appearance/domain/use_case/appearance_use_case.dart';

class AppearanceState extends Equatable {
  const AppearanceState({required this.appearance});

  final AppAppearance appearance;

  @override
  List<Object?> get props => [appearance];
}

/// Sits above `MaterialApp`, because changing the accent has to rebuild the
/// whole tree. Still a factory: the choice itself lives in the repository, so
/// this holds nothing that would be lost.
class AppearanceCubit extends Cubit<AppearanceState> {
  AppearanceCubit(this._useCase)
    : super(AppearanceState(appearance: _useCase.current())) {
    _subscription = _useCase.watch().listen((appearance) {
      if (!isClosed) emit(AppearanceState(appearance: appearance));
    });
  }

  final AppearanceUseCase _useCase;
  StreamSubscription<AppAppearance>? _subscription;

  Future<void> setAccent(AccentColor accent) => _useCase.setAccent(accent);

  Future<void> setMode(ThemeModePreference mode) => _useCase.setMode(mode);

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
