import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/core/di/injection.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/utils/open_file.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:shuttle/core/widgets/bounce_tap.dart';
import 'package:shuttle/core/widgets/selection_bar.dart';
import 'package:shuttle/core/widgets/transfer_progress_bar.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/sharing/presentation/pages/share_page.dart'
    show iconForFile;
import 'package:shuttle/features/transfer/presentation/bloc/peer_files_cubit.dart';

/// One device, both directions.
///
/// The screen was a list of the peer's files and nothing else, which made the
/// Receive tab read as a dead end: you tapped a device you had just found and
/// got a folder, with no sign the two were connected and no way to send
/// anything back. It now opens on the connection itself, then what has passed
/// between the two devices, then what the peer is offering — and sending is a
/// button rather than a thing you had to go back to the Share tab to arrange.
///
/// Owns a [PeerFilesCubit] scoped to this peer — created here, disposed with
/// the route. Two peer screens open at once would each get their own.
class PeerPage extends StatelessWidget {
  const PeerPage({
    required this.name,
    required this.host,
    required this.port,
    super.key,
  });

  final String name;
  final String host;
  final int port;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PeerFilesCubit>(param1: host, param2: port)..load(),
      child: _PeerView(name: name, host: host, port: port),
    );
  }
}

class _PeerView extends StatelessWidget {
  const _PeerView({required this.name, required this.host, required this.port});

  final String name;
  final String host;
  final int port;

  Future<void> _pickAndSend(BuildContext context) async {
    final cubit = context.read<PeerFilesCubit>();

    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null) return;

    final files = result.paths
        .whereType<String>()
        .map(File.new)
        .toList(growable: false);
    if (files.isNotEmpty) await cubit.send(files);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PeerFilesCubit>();

    return BlocConsumer<PeerFilesCubit, PeerFilesState>(
      listenWhen: (previous, current) => current.message != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(state.message!)));
        cubit.messageShown();
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name),
                Text('$host:$port', style: context.type.bodySmall),
              ],
            ),
            actions: [
              if (state.files.isNotEmpty)
                IconButton(
                  tooltip: state.allSelected ? 'Select none' : 'Select all',
                  icon: Icon(
                    state.allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                  ),
                  onPressed: cubit.toggleAll,
                ),
              IconButton(
                onPressed: state.status == PeerFilesStatus.loading
                    ? null
                    : cubit.load,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: Column(
            children: [
              if (state.progress != null)
                TransferProgressBar(
                  progress: state.progress!,
                  onCancel: cubit.cancel,
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space4,
                    AppTheme.space2,
                    AppTheme.space4,
                    AppTheme.space8,
                  ),
                  children: [
                    _ConnectionCard(
                      name: name,
                      host: host,
                      port: port,
                      state: state,
                      onRetry: cubit.load,
                    ),
                    const SizedBox(height: AppTheme.space4),
                    _SendButton(
                      name: name,
                      // Nothing can be pushed to a device that is not
                      // answering, and a picker that ends in a failed send is
                      // worse than a button that says not yet.
                      onTap: state.isConnected && !state.isBusy
                          ? () => _pickAndSend(context)
                          : null,
                    ),
                    const SizedBox(height: AppTheme.space6),
                    SectionLabel('Between you and $name'),
                    _Activity(events: state.activity, peerName: name),
                    const SizedBox(height: AppTheme.space6),
                    SectionLabel('$name is sharing'),
                    _SharedByPeer(state: state, cubit: cubit),
                  ],
                ),
              ),
              if (state.isSelecting)
                SelectionBar(
                  count: state.selected.length,
                  totalBytes: state.selectedBytes,
                  actionLabel: 'Download',
                  busy: state.isBusy,
                  onAction: cubit.downloadSelected,
                  onClear: cubit.clearSelection,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The top of the screen: that these two devices are talking, before anything
/// about files.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.name,
    required this.host,
    required this.port,
    required this.state,
    required this.onRetry,
  });

  final String name;
  final String host;
  final int port;
  final PeerFilesState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final unreachable = state.status == PeerFilesStatus.unreachable;
    final connecting = state.status == PeerFilesStatus.loading;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.space5),
      borderColor: unreachable
          ? palette.amber.withValues(alpha: 0.35)
          : (connecting ? null : palette.accent.withValues(alpha: 0.35)),
      child: Column(
        children: [
          Row(
            children: [
              FileIconTile(
                icon: unreachable
                    ? Icons.wifi_off_rounded
                    : Icons.devices_rounded,
                background: unreachable
                    ? palette.amber.withValues(alpha: 0.12)
                    : palette.accentSoft,
                color: unreachable ? palette.amber : palette.accent,
                size: 48,
              ),
              const SizedBox(width: AppTheme.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: context.type.titleLarge),
                    const SizedBox(height: 2),
                    Text('$host:$port', style: context.type.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.space2),
              StatusPill(
                label: switch (state.status) {
                  PeerFilesStatus.loading => 'Connecting',
                  PeerFilesStatus.ready => 'Connected',
                  PeerFilesStatus.unreachable => 'Not reachable',
                },
                tone: switch (state.status) {
                  PeerFilesStatus.loading => StatusTone.idle,
                  PeerFilesStatus.ready => StatusTone.live,
                  PeerFilesStatus.unreachable => StatusTone.warning,
                },
                pulsing: state.status == PeerFilesStatus.ready,
              ),
            ],
          ),
          if (unreachable) ...[
            const SizedBox(height: AppTheme.space4),
            Text(
              'It may have left the network or closed the app. Anything '
              'already exchanged is still listed below.',
              style: context.type.bodySmall,
            ),
            const SizedBox(height: AppTheme.space3),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The primary action, and the reason the screen exists in both directions.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: Text('Send files to $name', overflow: TextOverflow.ellipsis),
    );

    // The bounce is the app's press feedback for a primary action, but it owns
    // the gesture — so the button underneath is muted with IgnorePointer and
    // would run the action twice otherwise. Disabled, there is nothing to
    // bounce and the plain button paints its own dimmed state.
    if (onTap == null) return button;

    return BounceTap(
      onTap: onTap!,
      child: IgnorePointer(child: button),
    );
  }
}

/// What has actually moved between the two devices, both directions, newest
/// first.
class _Activity extends StatelessWidget {
  const _Activity({required this.events, required this.peerName});

  final List<TransferEvent> events;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (events.isEmpty) {
      return SurfaceCard(
        child: EmptyState(
          icon: Icons.swap_vert_rounded,
          title: 'Nothing yet',
          body:
              'Files you send to $peerName, and files it sends here, appear '
              'in this list.',
        ),
      );
    }

    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++)
            EntranceItem(
              index: i,
              child: Column(
                children: [
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
                          // The arrow, not the file type: on this screen which
                          // way it went is the thing being asked.
                          icon: event.incoming
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          background: event.incoming
                              ? palette.mintSoft
                              : palette.accentSoft,
                          color: event.incoming
                              ? palette.mint
                              : palette.accent,
                        ),
                        title: Text(
                          event.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${event.incoming ? 'Received' : 'Sent'} · '
                          '${event.sizeLabel} · ${event.whenLabel}'
                          '${openable ? '' : ' · not on this device'}',
                        ),
                        trailing: openable
                            ? Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: palette.textMuted,
                              )
                            : null,
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The peer's own share list — what you can pull from it.
class _SharedByPeer extends StatelessWidget {
  const _SharedByPeer({required this.state, required this.cubit});

  final PeerFilesState state;
  final PeerFilesCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (state.status == PeerFilesStatus.loading) {
      return const SurfaceCard(
        padding: EdgeInsets.all(AppTheme.space8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.status == PeerFilesStatus.unreachable) {
      return SurfaceCard(
        child: EmptyState(
          icon: Icons.wifi_off_rounded,
          tone: context.palette.amber,
          title: 'Cannot read its files',
          body: 'The device is not answering right now.',
        ),
      );
    }

    if (state.files.isEmpty) {
      return const SurfaceCard(
        child: EmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Nothing shared',
          body:
              'This device is not offering any files right now. On it, open '
              'Share and add some.',
        ),
      );
    }

    final palette = context.palette;

    return SurfaceCard(
      child: Column(
        children: [
          for (var index = 0; index < state.files.length; index++)
            EntranceItem(
              index: index,
              child: Builder(
                builder: (context) {
                  final file = state.files[index];
                  final selected = state.selected.contains(index);

                  return Column(
                    children: [
                      if (index > 0)
                        const Divider(
                          indent: AppTheme.space4,
                          endIndent: AppTheme.space4,
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: BoxDecoration(
                          color: selected
                              ? palette.accentSoft
                              : Colors.transparent,
                        ),
                        child: ListTile(
                          leading: state.isSelecting
                              ? SizedBox(
                                  width: 40,
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: (_) => cubit.toggle(index),
                                  ),
                                )
                              : FileIconTile(icon: iconForFile(file.name)),
                          title: Text(
                            file.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(file.readableSize),
                          onTap: state.isSelecting
                              ? () => cubit.toggle(index)
                              : (state.isBusy
                                    ? null
                                    : () => cubit.downloadOne(index)),
                          onLongPress: () => cubit.toggle(index),
                          trailing: state.isSelecting
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 18,
                                  ),
                                  // One at a time: two downloads through the
                                  // same repository would fight over one
                                  // progress slot.
                                  onPressed: state.isBusy
                                      ? null
                                      : () => cubit.downloadOne(index),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
