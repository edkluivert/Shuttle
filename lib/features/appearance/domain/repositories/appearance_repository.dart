import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';

abstract interface class AppearanceRepository {
  AppAppearance get current;

  Stream<AppAppearance> watch();

  Future<void> setAccent(AccentColor accent);

  Future<void> setMode(ThemeModePreference mode);
}
