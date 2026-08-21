import 'package:flutter/material.dart';
import 'package:shuttle/core/utils/formatters.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/app_ui.dart';

/// The bar that appears once files are selected: what is picked, how big it
/// is altogether, and the one action worth offering.
///
/// The total matters more than it looks — "copy 12 files" says nothing about
/// whether this is a two-second job or a ten-minute one.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    required this.count,
    required this.totalBytes,
    required this.actionLabel,
    required this.onAction,
    required this.onClear,
    this.busy = false,
    super.key,
  });

  final int count;
  final int totalBytes;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          AppTheme.space2,
          AppTheme.space4,
          AppTheme.space4,
        ),
        // Slides up rather than appearing: the bar arrives because of
        // something the user just did, and should look like a consequence.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: Opacity(opacity: value, child: child),
          ),
          child: SurfaceCard(
            color: palette.surfaceHigh,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space2,
              AppTheme.space2,
              AppTheme.space2,
              AppTheme.space2,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Clear selection',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        count == 1 ? '1 file' : '$count files',
                        style: context.type.titleSmall,
                      ),
                      if (totalBytes > 0)
                        Text(
                          formatBytes(totalBytes),
                          style: context.type.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.space2),
                FilledButton.icon(
                  onPressed: busy ? null : onAction,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(actionLabel),
                  style: FilledButton.styleFrom(
                    // The theme stretches buttons full-width for forms; here
                    // it sits in a row and must not.
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
