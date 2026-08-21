import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';
import 'package:shuttle/features/appearance/domain/repositories/appearance_repository.dart';

class AppearanceUseCase {
  const AppearanceUseCase(this._repository);

  final AppearanceRepository _repository;

  AppAppearance current() => _repository.current;

  Stream<AppAppearance> watch() => _repository.watch();

  Future<void> setAccent(AccentColor accent) => _repository.setAccent(accent);

  Future<void> setMode(ThemeModePreference mode) => _repository.setMode(mode);
}
