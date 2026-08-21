import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/sharing/domain/entities/server_status.dart';
import 'package:shuttle/features/sharing/domain/use_case/sharing_use_case.dart';

part 'sharing_event.dart';
part 'sharing_state.dart';

/// The Share screen's state.
///
/// A factory, created by the page that shows it: the server it reflects lives
/// in the repository and keeps running regardless, so nothing is lost when
/// this closes. A singleton bloc would have tied the server's lifetime to a
/// widget's, and left every other screen able to reach in and change it.
class SharingBloc extends Bloc<SharingEvent, SharingState> {
  SharingBloc(this._useCase) : super(SharingState(status: _useCase.status())) {
    on<SharingStarted>(_onStarted);
    on<SharingFilesAdded>(_onFilesAdded);
    on<SharingFileRemoved>(_onFileRemoved);
    on<SharingCleared>(_onCleared);
    on<SharingStatusChanged>(_onStatusChanged);

    _subscription = _useCase.watch().listen(
      (status) => add(SharingStatusChanged(status)),
    );
  }

  final SharingUseCase _useCase;
  StreamSubscription<ServerStatus>? _subscription;

  Future<void> _onStarted(SharingStarted event, Emitter<SharingState> emit) =>
      _useCase.start();

  void _onFilesAdded(SharingFilesAdded event, Emitter<SharingState> emit) =>
      _useCase.share(event.files);

  void _onFileRemoved(SharingFileRemoved event, Emitter<SharingState> emit) =>
      _useCase.unshareAt(event.index);

  void _onCleared(SharingCleared event, Emitter<SharingState> emit) =>
      _useCase.unshareAll();

  void _onStatusChanged(
    SharingStatusChanged event,
    Emitter<SharingState> emit,
  ) => emit(state.copyWith(status: event.status));

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
