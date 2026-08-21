import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presses in under the finger and springs back.
///
/// The scale is driven by an [AnimationController] rather than an implicit
/// tween so a quick tap still bounces: a press-and-release faster than the
/// animation would otherwise show nothing at all, which is exactly the tap
/// that most needs the feedback.
class BounceTap extends StatefulWidget {
  const BounceTap({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.minScale = 0.95,
    this.haptics = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far in it presses. Subtle on purpose — a button that shrinks by a
  /// tenth reads as a toy.
  final double minScale;

  final bool haptics;

  bool get isEnabled => onTap != null || onLongPress != null;

  @override
  State<BounceTap> createState() => _BounceTapState();
}

class _BounceTapState extends State<BounceTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() => _controller.forward();

  void _release() => _controller.reverse();

  void _tap() {
    if (widget.haptics) HapticFeedback.lightImpact();
    widget.onTap?.call();

    // A tap released before the press finished still gets a full bounce,
    // rather than a flicker at whatever scale it happened to reach.
    if (_controller.value < 0.4) {
      _controller.animateTo(0.45).then((_) {
        if (mounted) _controller.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: _tap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: 1 - ((1 - widget.minScale) * _controller.value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
