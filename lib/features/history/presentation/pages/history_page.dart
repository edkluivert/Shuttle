import 'package:flutter/material.dart';
import 'package:shuttle/core/utils/formatters.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/presentation/bloc/history_cubit.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/utils/open_file.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything this device has sent or received, grouped by day.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The shell already provides one, and the log lives in the repository
    // regardless — a second cubit here would just be another listener.
    return const _HistoryView();
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryCubit>().state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!history.isEmpty)
            TextButton(
              onPressed: () => _confirmClear(context),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: history.isEmpty
          ? const EmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing yet',
              body:
                  'Files you send or receive are listed here, so you can '
                  'check what has already been copied across.',
            )
          : _Body(history: history),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This only forgets the list. The files themselves are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await context.read<HistoryCubit>().clear();
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.history});

  final HistoryState history;

  @override
  Widget build(BuildContext context) {
    // Grouping lives on the state, so the page just renders it.
    final groups = history.byDay;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space4,
        AppTheme.space4,
        AppTheme.space8,
      ),
      children: [
        _Summary(history: history),
        const SizedBox(height: AppTheme.space6),
        for (final entry in groups.entries) ...[
          SectionLabel(_dayLabel(entry.key)),
          SurfaceCard(
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      indent: AppTheme.space4,
                      endIndent: AppTheme.space4,
                    ),
                  _EventRow(event: entry.value[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space5),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime day) {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final difference = startOfToday.difference(day).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '$difference days ago';
    return '${day.day}/${day.month}/${day.year}';
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.history});

  final HistoryState history;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.space5,
        horizontal: AppTheme.space4,
      ),
      child: Row(
        children: [
          _Stat(
            value: '${history.receivedCount}',
            label: 'received',
            color: palette.mint,
          ),
          _Divider(),
          _Stat(
            value: '${history.sentCount}',
            label: 'sent',
            color: palette.accent,
          ),
          _Divider(),
          _Stat(
            value: formatBytes(history.totalBytes),
            label: 'moved',
            color: palette.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: context.palette.border);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: context.type.headlineSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: context.type.bodySmall),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final TransferEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Checked per row rather than once for the list: a file can be deleted
    // while this screen is open, and an entry from before the log recorded
    // paths has nothing to check.
    final openable = event.existsLocally;

    return ListTile(
      onTap: openable ? () => openFromUi(context, event.path!) : null,
      leading: FileIconTile(
        // Direction is what the row is about, so it gets the icon and the
        // colour rather than the file type.
        icon: event.incoming
            ? Icons.south_west_rounded
            : Icons.north_east_rounded,
        background: event.incoming ? palette.mintSoft : palette.accentSoft,
        color: event.incoming ? palette.mint : palette.accent,
      ),
      title: Text(event.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${event.incoming ? 'From' : 'To'} ${event.peer}'
        '  ·  ${event.way.label}'
        // Said plainly rather than left as a row that does nothing when
        // tapped. The transfer still happened; the file has since moved.
        '${openable ? '' : '  ·  not on this device'}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(event.sizeLabel, style: context.type.bodySmall),
          Text(event.whenLabel, style: context.type.bodySmall),
        ],
      ),
    );
  }
}
