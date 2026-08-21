import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:shuttle/core/widgets/bounce_tap.dart';
import 'package:shuttle/features/appearance/domain/entities/app_appearance.dart';
import 'package:shuttle/features/appearance/presentation/bloc/appearance_cubit.dart';

/// Picking the accent and the light/dark preference.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AppearanceCubit>();
    final appearance = context.watch<AppearanceCubit>().state.appearance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          AppTheme.space4,
          AppTheme.space4,
          AppTheme.space8,
        ),
        children: [
          const SectionLabel('Accent'),
          SurfaceCard(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: Wrap(
              spacing: AppTheme.space4,
              runSpacing: AppTheme.space4,
              children: [
                for (final accent in AccentColor.values)
                  _AccentSwatch(
                    accent: accent,
                    selected: appearance.accent == accent,
                    onTap: () => cubit.setAccent(accent),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          const SectionLabel('Theme'),
          SurfaceCard(
            child: Column(
              children: [
                for (var i = 0; i < ThemeModePreference.values.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      indent: AppTheme.space4,
                      endIndent: AppTheme.space4,
                    ),
                  _ModeRow(
                    mode: ThemeModePreference.values[i],
                    selected: appearance.mode == ThemeModePreference.values[i],
                    onTap: () => cubit.setMode(ThemeModePreference.values[i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space6),
          const SectionLabel('Preview'),
          const _Preview(),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AccentColor accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The swatch shows the colour it would become, not the one in use — so
    // the row reads as a set of options rather than six copies of the
    // current theme.
    final preview = palette.withAccent(accent);

    return BounceTap(
      onTap: onTap,
      minScale: 0.9,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: preview.heroGradient,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? preview.accent : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: preview.accent.withValues(alpha: 0.35),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? Icon(Icons.check_rounded, color: preview.onAccent, size: 22)
                  : null,
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              accent.label,
              style: context.type.bodySmall?.copyWith(
                color: selected ? palette.accent : palette.textMuted,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeModePreference mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = switch (mode) {
      ThemeModePreference.system => Icons.brightness_auto_rounded,
      ThemeModePreference.light => Icons.light_mode_rounded,
      ThemeModePreference.dark => Icons.dark_mode_rounded,
    };

    return ListTile(
      onTap: onTap,
      leading: FileIconTile(
        icon: icon,
        background: selected ? palette.accentSoft : null,
        color: selected ? palette.accent : null,
      ),
      title: Text(mode.label),
      subtitle: mode == ThemeModePreference.system
          ? const Text('Follows your device setting')
          : null,
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: palette.accent, size: 20)
          : Icon(Icons.circle_outlined, color: palette.border, size: 20),
    );
  }
}

/// A miniature of the pieces the accent actually touches, so the choice can
/// be judged without leaving the screen.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: palette.heroGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.swap_vert_rounded,
                  color: palette.onAccent,
                  size: 19,
                ),
              ),
              const SizedBox(width: AppTheme.space3),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (bounds) =>
                      palette.heroGradient.createShader(bounds),
                  child: Text(
                    'http://192.168.1.5:53317',
                    style: context.type.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          Row(
            children: [
              const StatusPill(label: 'Online', tone: StatusTone.live),
              const SizedBox(width: AppTheme.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '2/7',
                  style: context.type.labelSmall?.copyWith(
                    color: palette.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: 0.62,
              minHeight: 5,
              backgroundColor: palette.border,
            ),
          ),
        ],
      ),
    );
  }
}
