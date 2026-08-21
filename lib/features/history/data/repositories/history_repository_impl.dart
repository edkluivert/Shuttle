import 'dart:async';

import 'package:shuttle/core/utils/current_and_changes.dart';
import 'package:shuttle/features/history/data/data_sources/history_local_data_source.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/repositories/history_repository.dart';

/// Holds the log in memory and writes it behind a debounce.
///
/// This is a singleton — the *repository* is, not the bloc. Three features
/// append to one list, and the screen showing it is created and destroyed as
/// the user navigates; the list has to outlive it.
class HistoryRepositoryImpl implements HistoryRepository {
  /// Copied into a growable list: the data source returns a fixed-length one
  /// (or `const []` when there is no file yet), and the first recorded
  /// transfer would fail to insert into it.
  HistoryRepositoryImpl(this._dataSource)
    : _events = List.of(_dataSource.read());

  /// Old entries stop being useful and the file should not grow forever.
  static const int _maxEntries = 500;

  final HistoryLocalDataSource _dataSource;
  final List<TransferEvent> _events;

  final StreamController<List<TransferEvent>> _controller =
      StreamController<List<TransferEvent>>.broadcast();

  Timer? _saveTimer;

  @override
  List<TransferEvent> get current => List.unmodifiable(_events);

  /// The current list first, so a screen opened long after the last
  /// transfer is not blank until the next one.
  @override
  Stream<List<TransferEvent>> watch() =>
      currentAndChanges(() => current, _controller.stream);

  @override
  Future<void> record(TransferEvent event) async {
    _events.insert(0, event);
    if (_events.length > _maxEntries) {
      _events.removeRange(_maxEntries, _events.length);
    }
    _controller.add(current);
    _scheduleSave();
  }

  @override
  Future<void> clear() async {
    if (_events.isEmpty) return;
    _events.clear();
    _controller.add(current);
    await _save();
  }

  /// A batch of twenty files should write the log once, not twenty times.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _dataSource.write(_events);
  }

  /// Flushes anything still pending. Called as the app closes — a debounce in
  /// flight would otherwise drop the last few entries.
  Future<void> dispose() async {
    if (_saveTimer?.isActive ?? false) await _save();
    _saveTimer?.cancel();
    await _controller.close();
  }
}
