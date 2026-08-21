import 'dart:io';

import 'package:flutter/material.dart';

/// Height of the macOS titlebar strip.
///
/// The bar is transparent and the app paints straight through it, but AppKit
/// still owns the strip: the traffic lights sit there and it is the region the
/// user grabs to move the window. Anything Flutter draws under it is visible
/// but not clickable, so the app's own chrome has to start below the line.
const double kMacTitlebarHeight = 28;

/// Reserves the titlebar strip by folding it into the view padding.
///
/// Doing it once around the shell rather than page by page means the existing
/// `SafeArea` in the tabs and the `AppBar` on every pushed screen already
/// account for it — both grow by `MediaQuery.padding.top`. On the phones the
/// inset is zero and the padding passes through untouched.
class MacTitlebarInset extends StatelessWidget {
  const MacTitlebarInset({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return child;

    final media = MediaQuery.of(context);
    // Added to the existing top padding rather than assigned over it: the
    // notch and the titlebar are separate claims on the same edge.
    final padded = media.padding.top + kMacTitlebarHeight;

    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: padded),
        viewPadding: media.viewPadding.copyWith(
          top: media.viewPadding.top + kMacTitlebarHeight,
        ),
      ),
      child: child,
    );
  }
}
