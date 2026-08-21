import 'package:equatable/equatable.dart';

/// The accents a user can pick between.
///
/// A closed set rather than a colour wheel: each one is a hand-checked pair
/// (accent plus the soft tint behind it) that has to stay legible on both the
/// light and the dark ground, and an arbitrary hex cannot promise that.
enum AccentColor {
  violet('Violet'),
  ocean('Ocean'),
  amber('Amber'),
  rose('Rose'),
  forest('Forest'),
  graphite('Graphite');

  const AccentColor(this.label);

  final String label;
}

/// Light, dark, or whatever the system is doing.
enum ThemeModePreference {
  system('System'),
  light('Light'),
  dark('Dark');

  const ThemeModePreference(this.label);

  final String label;
}

class AppAppearance extends Equatable {
  const AppAppearance({
    this.accent = AccentColor.violet,
    this.mode = ThemeModePreference.system,
  });

  final AccentColor accent;
  final ThemeModePreference mode;

  AppAppearance copyWith({AccentColor? accent, ThemeModePreference? mode}) =>
      AppAppearance(accent: accent ?? this.accent, mode: mode ?? this.mode);

  @override
  List<Object?> get props => [accent, mode];
}
