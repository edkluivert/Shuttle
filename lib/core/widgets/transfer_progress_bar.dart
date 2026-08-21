import 'package:flutter/material.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/app_ui.dart';

/// The live state of a transfer: what is moving, how much of it has arrived,
/// how fast, and how much longer.
///
/// One widget for both the network and USB paths — a copy over a cable and a
/// copy over Wi-Fi are the same event to the person watching, and they should
/// not look like two different features.
class TransferProgressBar extends StatelessWidget {
  const TransferProgressBar({
    required this.progress,
    required this.onCancel,
    super.key,
  });

  final TransferProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fraction = progress.fraction;

    final details = <String>[
      progress.bytesLabel,
      if (progress.speedLabel != null) progress.speedLabel!,
      if (progress.remainingLabel != null) progress.remainingLabel!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space2,
        AppTheme.space4,
        AppTheme.space3,
      ),
      child: SurfaceCard(
        color: palette.surfaceHigh,
        borderColor: palette.accent.withValues(alpha: 0.3),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          AppTheme.space3,
          AppTheme.space2,
          AppTheme.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (progress.isBatch) ...[
                  _BatchChip(progress: progress),
                  const SizedBox(width: AppTheme.space3),
                ],
                Expanded(
                  child: Text(
                    progress.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.titleSmall,
                  ),
                ),
                if (fraction != null)
                  Text(
                    '${(fraction * 100).round()}%',
                    style: context.type.titleSmall?.copyWith(
                      color: palette.accent,
                      // Without tabular figures the percentage jitters
                      // sideways as the digits change width.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Stop',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: TweenAnimationBuilder<double>(
                // Smooths the jumps between samples so the bar glides instead
                // of stepping — the transfer is continuous even though the
                // readings are not.
                tween: Tween(begin: 0, end: fraction ?? 0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: fraction == null ? null : value,
                  minHeight: 5,
                  backgroundColor: palette.border,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              details.join('  ·  '),
              style: context.type.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchChip extends StatelessWidget {
  const _BatchChip({required this.progress});

  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '${progress.fileIndex}/${progress.fileCount}',
        style: context.type.labelSmall?.copyWith(color: palette.accent),
      ),
    );
  }
}
