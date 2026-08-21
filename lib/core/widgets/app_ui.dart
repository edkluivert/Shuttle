import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/bounce_tap.dart';

/// The building blocks the screens are assembled from.
///
/// Kept together on purpose: a design system spread across a dozen files
/// stops being consulted, and the components drift.

// ── Surfaces ────────────────────────────────────────────────────────────

/// A panel. Border and tonal fill, never a shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.radius = AppTheme.radiusLg,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final content = Padding(padding: padding, child: child);

    // A Material, not a DecoratedBox. Anything inside that inks — a ListTile,
    // a Checkbox, an InkWell — paints its highlight onto the nearest Material
    // ancestor, so a DecoratedBox with a colour in between hid every splash
    // and hover behind the card's own fill. Painting the fill *as* the
    // Material puts the ink back on top of it, and `clipBehavior` keeps a
    // splash inside the rounded corners.
    return Material(
      color: color ?? palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
    );
  }
}

/// A quiet uppercase signpost above a group of content.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.space1,
        bottom: AppTheme.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: context.type.labelSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ── Status ──────────────────────────────────────────────────────────────

enum StatusTone { live, idle, warning, danger }

/// The small capsule that says what state something is in.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.tone = StatusTone.idle,
    this.pulsing = false,
    super.key,
  });

  final String label;
  final StatusTone tone;

  /// A slow breath on the dot, for states that are genuinely live. Anything
  /// that animates permanently stops meaning anything, so this is opt-in.
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (tone) {
      StatusTone.live => palette.mint,
      StatusTone.idle => palette.textMuted,
      StatusTone.warning => palette.amber,
      StatusTone.danger => palette.danger,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: color, pulsing: pulsing),
          const SizedBox(width: 7),
          Text(
            label,
            style: context.type.labelSmall?.copyWith(
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.pulsing
            ? Curves.easeInOut.transform(_controller.value)
            : 1.0;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.55 + (0.45 * t)),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * t),
                blurRadius: 6 * t,
                spreadRadius: 1.5 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Concentric rings breathing outward — the app's one piece of ornament,
/// reserved for "this device is visible on the network".
class PulseRings extends StatefulWidget {
  const PulseRings({required this.color, this.size = 92, super.key});

  final Color color;
  final double size;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _RingPainter(_controller.value, widget.color),
          child: child,
        ),
        child: Center(
          child: Icon(
            Icons.wifi_tethering_rounded,
            color: widget.color,
            size: widget.size * 0.32,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    // Three rings, evenly out of phase, each fading as it grows.
    for (var i = 0; i < 3; i++) {
      final progress = (t + (i / 3)) % 1.0;
      final radius = maxRadius * (0.3 + (0.7 * progress));
      final opacity = (1 - progress) * 0.35;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color;
}

// ── Navigation ──────────────────────────────────────────────────────────

class NavDestination {
  const NavDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// A floating segmented control, in place of Material's tab bar.
///
/// The selected pill slides between positions rather than cutting, which is
/// most of what makes navigation feel built rather than assembled.
class PillNav extends StatelessWidget {
  const PillNav({
    required this.destinations,
    required this.index,
    required this.onSelect,
    super.key,
  });

  final List<NavDestination> destinations;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space2,
        AppTheme.space4,
        AppTheme.space3,
      ),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: palette.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / destinations.length;

            return Stack(
              children: [
                AnimatedAlign(
                  alignment: Alignment(
                    destinations.length == 1
                        ? 0
                        : -1 + (2 * index / (destinations.length - 1)),
                    0,
                  ),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: width,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _NavItem(
                          destination: destinations[i],
                          selected: i == index,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? palette.onAccent : palette.textMuted;

    return BounceTap(
      onTap: onTap,
      minScale: 0.93,
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, size: 17, color: color),
            const SizedBox(width: 7),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: context.type.labelLarge!.copyWith(
                color: color,
                fontSize: 13.5,
              ),
              child: Text(destination.label),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty states ────────────────────────────────────────────────────────

/// The screen with nothing on it is the one people see most while they work
/// out what the app does, so it gets a real composition rather than a
/// centred icon.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.tone,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tone ?? palette.textMuted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.15)),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: AppTheme.space5),
            Text(title, style: context.type.titleMedium),
            const SizedBox(height: AppTheme.space2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: context.type.bodySmall,
            ),
            if (action != null) ...[
              const SizedBox(height: AppTheme.space6),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Motion ──────────────────────────────────────────────────────────────

/// Fades and lifts a list item into place, staggered by its position.
///
/// Capped at twelve items: past that the last rows would be waiting on an
/// animation nobody is still watching.
class EntranceItem extends StatelessWidget {
  const EntranceItem({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = math.min(index, 12) * 35;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The rounded icon tile used for every file row.
class FileIconTile extends StatelessWidget {
  const FileIconTile({
    required this.icon,
    this.color,
    this.background,
    this.size = 40,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? palette.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Icon(icon, size: size * 0.5, color: color ?? palette.textMuted),
    );
  }
}
