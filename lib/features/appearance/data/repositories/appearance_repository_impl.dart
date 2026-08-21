import 'dart:async';

import 'package:shuttle/core/utils/current_and_changes.dart';
import 'package:shuttle/features/appearance/data/data_sources/appearance_local_data_source.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';
import 'package:shuttle/features/appearance/domain/repositories/appearance_repository.dart';

class AppearanceRepositoryImpl implements AppearanceRepository {
  AppearanceRepositoryImpl(this._dataSource) : _appearance = _dataSource.read();

  final AppearanceLocalDataSource _dataSource;
  final StreamController<AppAppearance> _controller =
      StreamController<AppAppearance>.broadcast();

  AppAppearance _appearance;

  @override
  AppAppearance get current => _appearance;

  @override
  Stream<AppAppearance> watch() =>
      currentAndChanges(() => _appearance, _controller.stream);

  @override
  Future<void> setAccent(AccentColor accent) =>
      _update(_appearance.copyWith(accent: accent));

  @override
  Future<void> setMode(ThemeModePreference mode) =>
      _update(_appearance.copyWith(mode: mode));

  Future<void> _update(AppAppearance next) async {
    if (next == _appearance) return;
    _appearance = next;
    // Emitted before the write: the UI should turn over on the same frame as
    // the tap, not after a disk round trip.
    _controller.add(next);
    await _dataSource.write(next);
  }

  Future<void> dispose() => _controller.close();
}
