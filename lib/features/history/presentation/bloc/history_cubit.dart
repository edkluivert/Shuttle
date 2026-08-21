import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';

class HistoryState extends Equatable {
  const HistoryState({this.events = const []});

  final List<TransferEvent> events;

  bool get isEmpty => events.isEmpty;

  List<TransferEvent> recent(int count) =>
      List.unmodifiable(events.take(count));

  int get sentCount => events.where((e) => !e.incoming).length;
  int get receivedCount => events.where((e) => e.incoming).length;
  int get totalBytes => events.fold(0, (sum, e) => sum + e.bytes);

  /// Grouped by calendar day, newest day first — a flat list of 300 rows
  /// gives no sense of when anything happened.
  Map<DateTime, List<TransferEvent>> get byDay {
    final groups = <DateTime, List<TransferEvent>>{};
    for (final event in events) {
      groups.putIfAbsent(event.day, () => []).add(event);
    }
    return groups;
  }

  HistoryState copyWith({List<TransferEvent>? events}) =>
      HistoryState(events: events ?? this.events);

  @override
  List<Object?> get props => [events];
}

/// Created wherever history is shown, and thrown away with that screen.
///
/// The log itself lives in the repository, so nothing is lost when this is
/// disposed — which is exactly why the bloc does not need to be a singleton.
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._useCase) : super(const HistoryState()) {
    _subscription = _useCase.watch().listen((events) {
      if (!isClosed) emit(state.copyWith(events: events));
    });
  }

  final HistoryUseCase _useCase;
  StreamSubscription<List<TransferEvent>>? _subscription;

  Future<void> clear() => _useCase.clear();

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
