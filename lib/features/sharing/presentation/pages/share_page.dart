import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shuttle/core/utils/formatters.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/presentation/bloc/history_cubit.dart';
import 'package:shuttle/features/sharing/domain/entities/server_status.dart';
import 'package:shuttle/features/sharing/domain/entities/shared_file.dart';
import 'package:shuttle/features/sharing/presentation/bloc/sharing_bloc.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/utils/open_file.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:shuttle/features/usb/presentation/widgets/usb_help_sheet.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shuttle/core/navigation/app_routes.dart';
import 'package:shuttle/core/widgets/bounce_tap.dart';

/// What this device is handing out, and how to come and get it.
class SharePage extends StatelessWidget {
  const SharePage({super.key});

  Future<void> _pick(BuildContext context) async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || !context.mounted) return;

    final files = result.paths
        .whereType<String>()
        .map(File.new)
        .toList(growable: false);
    if (files.isNotEmpty) {
      context.read<SharingBloc>().add(SharingFilesAdded(files));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SharingBloc>().state.status;
    final history = context.watch<HistoryCubit>().state;
    final files = status.files;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            0,
            AppTheme.space4,
            96,
          ),
          children: [
            const _AddressHero(),
            const SizedBox(height: AppTheme.space6),
            SectionLabel(
              'Sharing',
              trailing: files.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => context.read<SharingBloc>().add(
                        const SharingCleared(),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Clear'),
                    ),
            ),
            if (files.isEmpty)
              SurfaceCard(
                child: EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'Nothing shared yet',
                  body:
                      'Files you add can be picked up by any device on this '
                      'network, or from a browser.',
                ),
              )
            else ...[
              SurfaceCard(
                child: Column(
                  children: [
                    for (var i = 0; i < files.length; i++)
                      EntranceItem(
                        index: i,
                        child: _SharedRow(
                          file: files[i],
                          divided: i > 0,
                          onRemove: () => context.read<SharingBloc>().add(
                            SharingFileRemoved(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.space3),
              Padding(
                padding: const EdgeInsets.only(left: AppTheme.space1),
                child: Text(
                  '${files.length} file${files.length == 1 ? '' : 's'}'
                  '  ·  ${formatBytes(status.totalBytes)}',
                  style: context.type.bodySmall,
                ),
              ),
            ],
            if (!history.isEmpty) ...[
              const SizedBox(height: AppTheme.space6),
              SectionLabel(
                'Recent activity',
                trailing: TextButton(
                  onPressed: () => context.pushNamed(RouteNames.history),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('See all'),
                ),
              ),
              _ActivityList(events: history.recent(4)),
            ],
          ],
        ),
        // Floats over the list so the primary action is always in reach,
        // however far down the file list runs.
        Positioned(
          left: AppTheme.space4,
          right: AppTheme.space4,
          bottom: AppTheme.space4,
          child: _AddButton(onTap: () => _pick(context)),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        // The only shadow in the app, and only because this element floats
        // over scrolling content and has to separate from it.
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // The app's primary action, so it gets the press-in feedback.
      child: BounceTap(
        onTap: onTap,
        // IgnorePointer, not a null callback: the gesture belongs to the
        // bounce, but the button must still paint as enabled. Leaving both
        // live would run the action twice per tap.
        child: IgnorePointer(
          child: FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add files'),
          ),
        ),
      ),
    );
  }
}

/// The address card: the whole point of the browser support, so it gets the
/// weight of a hero rather than a row of text.
class _AddressHero extends StatelessWidget {
  const _AddressHero();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = context.watch<SharingBloc>().state.status;
    final url = status.primaryUrl;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OPEN ON ANY DEVICE', style: context.type.labelSmall),
                    const SizedBox(height: AppTheme.space3),
                    if (url == null)
                      Text(
                        'Waiting for a network…',
                        style: context.type.headlineSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      )
                    else
                      ShaderMask(
                        // The address is the single most important string in
                        // the app; the gradient is spent here and on the app
                        // mark, nowhere else.
                        shaderCallback: (bounds) =>
                            palette.heroGradient.createShader(bounds),
                        child: Text(
                          url,
                          style: context.type.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (url != null) PulseRings(color: palette.mint, size: 72),
            ],
          ),
          const SizedBox(height: AppTheme.space3),
          Text(
            url == null
                ? 'Connect to Wi-Fi, or plug in a cable and turn on tethering.'
                : 'Open this address on the device you want to move files '
                      'to or from — the phone, laptop or tablet at the other '
                      'end. Nothing to install there.',
            style: context.type.bodySmall,
          ),
          if (url != null) ...[
            const SizedBox(height: AppTheme.space4),
            Row(
              children: [
                _HeroAction(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Address copied')),
                    );
                  },
                ),
                const SizedBox(width: AppTheme.space2),
                _HeroAction(
                  icon: Icons.usb_rounded,
                  label: 'Over USB',
                  onTap: () => showUsbHelpSheet(context),
                ),
                if (status.addresses.length > 1) ...[
                  const SizedBox(width: AppTheme.space2),
                  _HeroAction(
                    icon: Icons.lan_outlined,
                    // More than one address means more than one network —
                    // Wi-Fi and a USB tether, typically — and only one of them
                    // is the one the other device is on.
                    label: '+${status.addresses.length - 1}',
                    onTap: () => _showAllAddresses(context, status),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showAllAddresses(BuildContext context, ServerStatus status) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space5,
            0,
            AppTheme.space5,
            AppTheme.space5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('All addresses', style: context.type.titleLarge),
              const SizedBox(height: AppTheme.space1),
              Text(
                'One per network this device is on. If one does not work, '
                'try the next.',
                style: context.type.bodySmall,
              ),
              const SizedBox(height: AppTheme.space4),
              for (final address in status.addresses)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space2),
                  child: SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space4,
                      vertical: AppTheme.space3,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lan_outlined,
                          size: 18,
                          color: context.palette.textMuted,
                        ),
                        const SizedBox(width: AppTheme.space3),
                        Expanded(
                          child: SelectableText(
                            'http://$address:${status.port}',
                            style: context.type.bodyLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(
                              text: 'http://$address:${status.port}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return BounceTap(
      onTap: onTap,
      minScale: 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: palette.textPrimary),
              const SizedBox(width: 7),
              Text(
                label,
                style: context.type.labelLarge?.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedRow extends StatelessWidget {
  const _SharedRow({
    required this.file,
    required this.divided,
    required this.onRemove,
  });

  final SharedFile file;
  final bool divided;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (divided)
          const Divider(indent: AppTheme.space4, endIndent: AppTheme.space4),
        ListTile(
          // These are this device's own files, picked from disk — openable
          // for the same reason a received one is.
          onTap: file.path == null
              ? null
              : () => openFromUi(context, file.path!),
          leading: FileIconTile(icon: iconForFile(file.name)),
          title: Text(file.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(file.readableSize),
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Stop sharing',
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}

/// What has actually moved, and in which direction.
///
/// This is the answer to "who is copying from whom": a browser on the network
/// can take a file or drop one off without the app saying a word, which makes
/// a transfer that worked look identical to one that never happened.
class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.events});

  final List<TransferEvent> events;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0)
              const Divider(
                indent: AppTheme.space4,
                endIndent: AppTheme.space4,
              ),
            Builder(
              builder: (context) {
                final event = events[i];
                final openable = event.existsLocally;

                return ListTile(
                  onTap: openable
                      ? () => openFromUi(context, event.path!)
                      : null,
                  leading: FileIconTile(
                    // Direction is the whole point, so it gets the icon and
                    // the colour rather than the file type.
                    icon: event.incoming
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    background: event.incoming
                        ? palette.mintSoft
                        : palette.accentSoft,
                    color: event.incoming ? palette.mint : palette.accent,
                  ),
                  title: Text(event.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    event.incoming
                        ? 'Received from ${event.peer}'
                        : '${event.peer} downloaded this',
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
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// A glanceable icon beats a generic page for every row.
IconData iconForFile(String name) {
  final ext = name.toLowerCase().split('.').last;
  const images = {'jpg', 'jpeg', 'png', 'gif', 'heic', 'webp', 'bmp'};
  const videos = {'mp4', 'mov', 'm4v', 'avi', 'mkv'};
  const audio = {'mp3', 'm4a', 'wav', 'aac', 'flac'};
  const archives = {'zip', 'rar', '7z', 'tar', 'gz'};
  const docs = {'pdf', 'doc', 'docx', 'pages', 'txt', 'md', 'rtf'};

  if (images.contains(ext)) return Icons.image_outlined;
  if (videos.contains(ext)) return Icons.movie_outlined;
  if (audio.contains(ext)) return Icons.music_note_outlined;
  if (archives.contains(ext)) return Icons.folder_zip_outlined;
  if (docs.contains(ext)) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}
