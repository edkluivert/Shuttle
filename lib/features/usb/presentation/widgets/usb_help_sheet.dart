import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shuttle/features/sharing/data/data_sources/http_server_data_source.dart';

/// Explains the one thing about USB that nobody guesses: plugging the cable in
/// does not create a network.
///
/// A phone connected as MTP (or as a camera, or just charging) exposes its
/// storage to the computer over a USB protocol — there is no IP link, so
/// there is nothing for this app to find. Two things do create one, and both
/// are two taps away.
Future<void> showUsbHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _UsbHelpSheet(),
  );
}

class _UsbHelpSheet extends StatelessWidget {
  const _UsbHelpSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transferring over USB', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'A USB cable on its own does not connect the two devices to a '
              'network. If your phone shows up as a drive (MTP), that is file '
              'storage only — this app will not see it. Pick one of these.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _Step(
              number: '1',
              title: 'USB tethering — easiest',
              body:
                  'On Android: Settings → Connections → Mobile hotspot and '
                  'tethering → USB tethering.\n'
                  'On iPhone: Settings → Personal Hotspot, then trust the '
                  'computer.\n\n'
                  'This makes a real network over the cable. A new address '
                  'appears on the Share tab — use that one.',
            ),
            const SizedBox(height: 20),
            _Step(
              number: '2',
              title: 'Android debugging — no tethering needed',
              body:
                  'With USB debugging on, run this on the computer, then '
                  'open the address below in any browser.',
            ),
            const SizedBox(height: 12),
            const _CopyableCommand(
              command:
                  'adb forward tcp:${HttpServerDataSource.preferredPort} '
                  'tcp:${HttpServerDataSource.preferredPort}',
              caption: 'Reach the phone from the computer',
            ),
            const SizedBox(height: 10),
            const _CopyableCommand(
              command: 'http://localhost:${HttpServerDataSource.preferredPort}',
              caption: 'Then open this on the computer',
            ),
            const SizedBox(height: 10),
            const _CopyableCommand(
              command:
                  'adb reverse tcp:${HttpServerDataSource.preferredPort} '
                  'tcp:${HttpServerDataSource.preferredPort}',
              caption: 'Or the other way: reach the computer from the phone',
            ),
            const SizedBox(height: 24),
            Text(
              'Wi-Fi needs none of this — both devices on the same network '
              'find each other on their own.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            number,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyableCommand extends StatelessWidget {
  const _CopyableCommand({required this.command, required this.caption});

  final String command;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
    );
  }
}

/// Whether to bother offering the USB route at all — it is only meaningful
/// where a cable is a realistic option.
bool get usbTransferIsRelevant =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isWindows ||
    Platform.isLinux;
