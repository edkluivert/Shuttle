import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';

abstract interface class AppearanceLocalDataSource {
  AppAppearance read();

  Future<void> write(AppAppearance appearance);
}

class AppearanceLocalDataSourceImpl implements AppearanceLocalDataSource {
  AppearanceLocalDataSourceImpl(this.file);

  final File file;

  @override
  AppAppearance read() {
    try {
      if (!file.existsSync()) return const AppAppearance();
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      return AppAppearance(
        // An unknown name means a theme from a newer build, or a corrupted
        // file. Falling back beats refusing to start.
        accent: AccentColor.values.firstWhere(
          (a) => a.name == json['accent'],
          orElse: () => AccentColor.violet,
        ),
        mode: ThemeModePreference.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => ThemeModePreference.system,
        ),
      );
    } catch (e) {
      debugPrint('Could not read appearance: $e');
      return const AppAppearance();
    }
  }

  @override
  Future<void> write(AppAppearance appearance) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'accent': appearance.accent.name,
          'mode': appearance.mode.name,
        }),
      );
    } catch (e) {
      debugPrint('Could not save appearance: $e');
    }
  }
}
