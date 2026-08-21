import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/discovery/domain/entities/peer.dart';
import 'package:shuttle/features/discovery/domain/use_case/discovery_use_case.dart';

class DiscoveryState extends Equatable {
  const DiscoveryState({this.peers = const [], this.hasError = false});

  final List<Peer> peers;
  final bool hasError;

  DiscoveryState copyWith({List<Peer>? peers, bool? hasError}) =>
      DiscoveryState(
        peers: peers ?? this.peers,
        hasError: hasError ?? this.hasError,
      );

  @override
  List<Object?> get props => [peers, hasError];
}

/// Created by the Receive page. The browse itself is owned by the repository
/// and keeps running, so leaving the tab does not restart discovery.
class DiscoveryCubit extends Cubit<DiscoveryState> {
  DiscoveryCubit(this._useCase) : super(const DiscoveryState()) {
    _subscription = _useCase.watchPeers().listen((peers) {
      if (isClosed) return;
      emit(
        state.copyWith(peers: peers, hasError: _useCase.lastError() != null),
      );
    });
  }

  final DiscoveryUseCase _useCase;
  StreamSubscription<List<Peer>>? _subscription;

  Future<void> refresh() => _useCase.refresh();

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
