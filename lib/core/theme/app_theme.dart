import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';

/// The design system.
///
/// Stock Material with a seed colour makes every app look like every other
/// app. This defines the palette, the type scale and the shapes explicitly so
/// the product has a face of its own: a dark, calm, technical surface with one
/// vivid accent, borders rather than shadows, and generous spacing.
///
/// Colours that are not part of Material's scheme — the hairline border, the
/// "connected" mint, the muted text — live on [AppPalette], reached through
/// `context.palette`, so no widget has to hardcode a hex value.
class AppTheme {
  const AppTheme._();

  // ── Rhythm ────────────────────────────────────────────────────────────
  // One spacing scale, used everywhere. Ad-hoc paddings are what make a
  // layout feel approximate.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;

  static ThemeData dark([AccentColor accent = AccentColor.violet]) =>
      _build(AppPalette.dark.withAccent(accent));

  static ThemeData light([AccentColor accent = AccentColor.violet]) =>
      _build(AppPalette.light.withAccent(accent));

  static ThemeData _build(AppPalette palette) {
    final scheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: palette.accent,
      secondary: palette.mint,
      onSecondary: palette.onAccent,
      secondaryContainer: palette.mintSoft,
      onSecondaryContainer: palette.mint,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.background,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textMuted,
      outline: palette.border,
      outlineVariant: palette.border,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceHigh,
      surfaceContainerHighest: palette.surfaceHigh,
    );

    final text = _typography(palette);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      textTheme: text,
      // Shadows are the first thing that dates an interface. Depth here comes
      // from tonal fills and a one-pixel border instead.
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: palette.textPrimary),
        systemOverlayStyle: palette.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space4,
          vertical: space1,
        ),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: palette.textMuted),
        iconColor: palette.textMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          minimumSize: const Size.fromHeight(50),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: palette.border),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: palette.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: text.bodyMedium?.copyWith(color: palette.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        insetPadding: const EdgeInsets.all(space4),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: palette.border, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.border,
        circularTrackColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: palette.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: palette.border),
        ),
      ),
      extensions: [palette],
    );
  }

  /// Tighter than Material's defaults, with negative tracking on the large
  /// sizes — the single change that most separates a designed interface from
  /// a default one.
  static TextTheme _typography(AppPalette palette) {
    final primary = palette.textPrimary;
    final muted = palette.textMuted;

    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 15.5,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: primary),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
      labelLarge: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      // Section headers: small, spaced, uppercase — the quiet signposting
      // that lets the content itself stay unshouty.
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: muted,
      ),
    );
  }
}

/// Every colour the design uses that Material's scheme has no slot for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.mint,
    required this.mintSoft,
    required this.amber,
    required this.danger,
  });

  final Brightness brightness;

  /// The page behind everything.
  final Color background;

  /// Cards and raised panels.
  final Color surface;
  final Color surfaceHigh;

  /// The hairline that does the work a shadow used to.
  final Color border;

  final Color textPrimary;
  final Color textMuted;

  /// The one vivid colour, used sparingly enough to still mean something.
  final Color accent;
  final Color accentSoft;
  final Color onAccent;

  /// Connected, transferring, done.
  final Color mint;
  final Color mintSoft;

  final Color amber;
  final Color danger;

  /// Deep ink with a violet cast, rather than pure grey — a neutral that has
  /// a temperature reads as considered; #000000 reads as unset.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0C11),
    surface: Color(0xFF13151C),
    surfaceHigh: Color(0xFF191C25),
    border: Color(0xFF242833),
    textPrimary: Color(0xFFF3F5F9),
    textMuted: Color(0xFF8E97AB),
    accent: Color(0xFF7C5CFF),
    accentSoft: Color(0xFF1D1A33),
    onAccent: Color(0xFFFFFFFF),
    mint: Color(0xFF2DD4A7),
    mintSoft: Color(0xFF10281F),
    amber: Color(0xFFF5B94A),
    danger: Color(0xFFFF6B6B),
  );

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF7F8FC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1F3F9),
    border: Color(0xFFE4E7F0),
    textPrimary: Color(0xFF0D1017),
    textMuted: Color(0xFF636D82),
    accent: Color(0xFF6344F5),
    accentSoft: Color(0xFFEDE9FF),
    onAccent: Color(0xFFFFFFFF),
    mint: Color(0xFF0FA97F),
    mintSoft: Color(0xFFE0F7F0),
    amber: Color(0xFFB9820C),
    danger: Color(0xFFE5484D),
  );

  /// The accent trio for each choice: the colour itself, the soft tint that
  /// sits behind it, and the second colour the hero gradient runs into.
  ///
  /// Hand-paired rather than generated. A tint derived by lowering opacity
  /// looks muddy on the dark ground and washed out on the light one, so each
  /// pair is picked per brightness.
  static const Map<AccentColor, ({Color accent, Color soft, Color companion})>
  _darkAccents = {
    AccentColor.violet: (
      accent: Color(0xFF7C5CFF),
      soft: Color(0xFF1D1A33),
      companion: Color(0xFF2DD4A7),
    ),
    AccentColor.ocean: (
      accent: Color(0xFF3B9EFF),
      soft: Color(0xFF11202F),
      companion: Color(0xFF56E1D4),
    ),
    AccentColor.amber: (
      accent: Color(0xFFFF9F45),
      soft: Color(0xFF2A1C10),
      companion: Color(0xFFFFD166),
    ),
    AccentColor.rose: (
      accent: Color(0xFFFF6B9A),
      soft: Color(0xFF2C1421),
      companion: Color(0xFFFFB37B),
    ),
    AccentColor.forest: (
      accent: Color(0xFF3ECF8E),
      soft: Color(0xFF10261D),
      companion: Color(0xFFA8E05F),
    ),
    AccentColor.graphite: (
      accent: Color(0xFF9AA6BF),
      soft: Color(0xFF1B1F28),
      companion: Color(0xFFCBD5E6),
    ),
  };

  static const Map<AccentColor, ({Color accent, Color soft, Color companion})>
  _lightAccents = {
    AccentColor.violet: (
      accent: Color(0xFF6344F5),
      soft: Color(0xFFEDE9FF),
      companion: Color(0xFF0FA97F),
    ),
    AccentColor.ocean: (
      accent: Color(0xFF0F72D9),
      soft: Color(0xFFE3F0FF),
      companion: Color(0xFF0DA5A0),
    ),
    AccentColor.amber: (
      accent: Color(0xFFC96A11),
      soft: Color(0xFFFFF0DE),
      companion: Color(0xFFD9A400),
    ),
    AccentColor.rose: (
      accent: Color(0xFFD6336F),
      soft: Color(0xFFFFE6EE),
      companion: Color(0xFFE07A4A),
    ),
    AccentColor.forest: (
      accent: Color(0xFF12885E),
      soft: Color(0xFFDFF5EA),
      companion: Color(0xFF6FA828),
    ),
    AccentColor.graphite: (
      accent: Color(0xFF4A5468),
      soft: Color(0xFFE9ECF3),
      companion: Color(0xFF77839B),
    ),
  };

  /// This palette with a different accent applied. The neutrals never move —
  /// only the one colour the user chose, and the colour the gradient runs
  /// into, so every theme keeps the same calm ground.
  AppPalette withAccent(AccentColor accent) {
    final swatch = brightness == Brightness.dark
        ? _darkAccents[accent]!
        : _lightAccents[accent]!;

    return copyWith(
      accent: swatch.accent,
      accentSoft: swatch.soft,
      mint: swatch.companion,
    );
  }

  /// The signature gradient: accent into its companion, used on the hero and
  /// nowhere else, so it stays an accent rather than a wallpaper.
  LinearGradient get heroGradient => LinearGradient(
    colors: [accent, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? mint,
    Color? mintSoft,
    Color? amber,
    Color? danger,
  }) => AppPalette(
    brightness: brightness ?? this.brightness,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    onAccent: onAccent ?? this.onAccent,
    mint: mint ?? this.mint,
    mintSoft: mintSoft ?? this.mintSoft,
    amber: amber ?? this.amber,
    danger: danger ?? this.danger,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      mintSoft: Color.lerp(mintSoft, other.mintSoft, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension PaletteAccess on BuildContext {
  /// `context.palette.mint` — the colours Material's scheme cannot name.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;

  TextTheme get type => Theme.of(this).textTheme;
}
