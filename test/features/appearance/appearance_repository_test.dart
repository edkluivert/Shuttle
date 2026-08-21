import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/features/appearance/data/data_sources/appearance_local_data_source.dart';
import 'package:shuttle/features/appearance/data/repositories/appearance_repository_impl.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late File file;

  AppearanceRepositoryImpl build() =>
      AppearanceRepositoryImpl(AppearanceLocalDataSourceImpl(file));

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lft_appearance');
    file = File(p.join(temp.path, 'appearance.json'));
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('remembering the choice', () {
    test('starts on the defaults', () {
      final repository = build();
      expect(repository.current.accent, AccentColor.violet);
      expect(repository.current.mode, ThemeModePreference.system);
    });

    test('survives a restart', () async {
      await build().setAccent(AccentColor.amber);
      expect(build().current.accent, AccentColor.amber);
    });

    test('accent and mode are remembered independently', () async {
      final repository = build();
      await repository.setAccent(AccentColor.ocean);
      await repository.setMode(ThemeModePreference.dark);

      final reopened = build();
      expect(reopened.current.accent, AccentColor.ocean);
      expect(reopened.current.mode, ThemeModePreference.dark);
    });

    test('announces every change to whoever is listening', () async {
      final repository = build();
      final seen = <AccentColor>[];
      final subscription =
          repository.watch().listen((a) => seen.add(a.accent));

      await repository.setAccent(AccentColor.rose);
      await repository.setAccent(AccentColor.forest);
      await Future<void>.delayed(Duration.zero);

      // The current value first, then each change.
      expect(seen, [AccentColor.violet, AccentColor.rose, AccentColor.forest]);
      await subscription.cancel();
    });

    test('setting the same value again says nothing', () async {
      final repository = build();
      var emissions = 0;
      final subscription = repository.watch().listen((_) => emissions++);

      await repository.setAccent(AccentColor.violet);
      await Future<void>.delayed(Duration.zero);

      expect(emissions, 1, reason: 'only the initial value');
      await subscription.cancel();
    });

    test('an accent from a newer build falls back rather than throwing', () {
      file.writeAsStringSync(jsonEncode({'accent': 'ultramarine', 'mode': 'dark'}));

      final repository = build();
      expect(repository.current.accent, AccentColor.violet);
      // The half it *can* read is still honoured.
      expect(repository.current.mode, ThemeModePreference.dark);
    });

    test('a corrupt file reads as the defaults', () {
      file.writeAsStringSync('{not json');
      expect(build().current, const AppAppearance());
    });
  });

  group('what an accent changes', () {
    test('every accent has a swatch in both brightnesses', () {
      // A missing entry would throw on the null assertion inside withAccent,
      // which is the kind of thing only found by tapping every swatch.
      for (final accent in AccentColor.values) {
        expect(() => AppPalette.dark.withAccent(accent), returnsNormally);
        expect(() => AppPalette.light.withAccent(accent), returnsNormally);
      }
    });

    test('the accent moves but the ground does not', () {
      final violet = AppPalette.dark.withAccent(AccentColor.violet);
      final amber = AppPalette.dark.withAccent(AccentColor.amber);

      expect(amber.accent, isNot(violet.accent));
      // The neutrals are the app's character; only the one colour changes.
      expect(amber.background, violet.background);
      expect(amber.surface, violet.surface);
      expect(amber.textPrimary, violet.textPrimary);
    });

    test('light and dark get different swatches for the same choice', () {
      // A colour legible on near-black is rarely legible on near-white.
      expect(
        AppPalette.light.withAccent(AccentColor.ocean).accent,
        isNot(AppPalette.dark.withAccent(AccentColor.ocean).accent),
      );
    });

    test('the theme carries the chosen accent through to the scheme', () {
      final theme = AppTheme.dark(AccentColor.forest);
      final palette = theme.extension<AppPalette>()!;

      expect(theme.colorScheme.primary, palette.accent);
      expect(palette.accent, AppPalette.dark.withAccent(AccentColor.forest).accent);
    });

    test('the gradient runs accent → companion, not accent → accent', () {
      // Two identical stops would render as a flat fill and quietly lose the
      // one flourish the design has.
      final palette = AppPalette.dark.withAccent(AccentColor.rose);
      final colors = palette.heroGradient.colors;

      expect(colors.first, palette.accent);
      expect(colors.last, isNot(palette.accent));
    });
  });
}
