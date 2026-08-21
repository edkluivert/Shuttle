import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shuttle/core/utils/formatters.dart';
import 'package:shuttle/core/utils/open_file.dart';
import 'package:shuttle/features/sharing/presentation/pages/share_page.dart'
    show iconForFile;
import 'package:shuttle/features/discovery/domain/entities/peer.dart';
import 'package:shuttle/features/discovery/presentation/bloc/discovery_cubit.dart';
import 'package:shuttle/features/transfer/domain/use_case/transfer_use_case.dart';
import 'package:shuttle/core/di/injection.dart';
import 'package:shuttle/features/sharing/presentation/bloc/sharing_bloc.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shuttle/core/navigation/app_routes.dart';

/// Devices you can pull from, and everything that has arrived.
class ReceivePage extends StatelessWidget {
  const ReceivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final discovery = context.watch<DiscoveryCubit>().state;
    // Uploads from the browser land through the server, so watching the
    // share state keeps the received list honest without polling the disk.
    context.watch<SharingBloc>();

    return RefreshIndicator(
      onRefresh: context.read<DiscoveryCubit>().refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          0,
          AppTheme.space4,
          AppTheme.space8,
        ),
        children: [
          SectionLabel(
            'Nearby devices',
            trailing: _RefreshButton(
              onTap: context.read<DiscoveryCubit>().refresh,
            ),
          ),
          if (discovery.peers.isNotEmpty && !discovery.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space3),
              child: Text(
                'Open one to send files to it, or take what it is sharing.',
                style: context.type.bodySmall,
              ),
            ),
          if (discovery.hasError)
            SurfaceCard(
              child: EmptyState(
                icon: Icons.wifi_off_rounded,
                tone: context.palette.amber,
                title: 'Could not search the network',
                body:
                    'Check that this device is on Wi-Fi and that local '
                    'network access is allowed for this app.',
              ),
            )
          else if (discovery.peers.isEmpty)
            const _SearchingCard()
          else
            SurfaceCard(
              child: Column(
                children: [
                  for (var i = 0; i < discovery.peers.length; i++)
                    EntranceItem(
                      index: i,
                      child: _PeerRow(peer: discovery.peers[i], divided: i > 0),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppTheme.space6),
          const SectionLabel('Received'),
          const _ReceivedList(),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh_rounded,
              size: 14,
              color: context.palette.textMuted,
            ),
            const SizedBox(width: 5),
            Text('Scan', style: context.type.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer, required this.divided});

  final Peer peer;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      children: [
        if (divided)
          const Divider(indent: AppTheme.space4, endIndent: AppTheme.space4),
        ListTile(
          leading: FileIconTile(
            icon: Icons.devices_rounded,
            background: palette.accentSoft,
            color: palette.accent,
          ),
          title: Text(peer.name),
          // What tapping does, not what the device's address is. The address
          // told the user nothing they could act on, and the row read as a
          // folder rather than as a device you can open a session with.
          subtitle: Text(
            peer.isReachable ? 'Tap to connect' : 'Resolving…',
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          // Unresolved services have no address to dial yet; tapping one
          // would just fail, so it stays disabled until it resolves.
          enabled: peer.isReachable,
          onTap: !peer.isReachable
              ? null
              : () => context.push(
                  AppRoutes.peerPath(
                    host: peer.host!,
                    port: peer.port!,
                    name: peer.name,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ReceivedList extends StatelessWidget {
  const _ReceivedList();

  @override
  Widget build(BuildContext context) {
    // Read through the use case rather than a bloc: this is a directory
    // listing with no state of its own, and the rebuild is already driven by
    // the share state above.
    final transfer = sl<TransferUseCase>();

    return FutureBuilder<List<File>>(
      future: transfer.inboxContents(),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <File>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            files.isEmpty) {
          return const SurfaceCard(
            padding: EdgeInsets.all(AppTheme.space8),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (files.isEmpty) {
          return SurfaceCard(
            child: EmptyState(
              icon: Icons.inbox_rounded,
              title: 'Nothing received yet',
              body:
                  'Files you pull from another device, or drop onto the web '
                  'page, land here.',
            ),
          );
        }

        return Column(
          children: [
            SurfaceCard(
              child: Column(
                children: [
                  for (var i = 0; i < files.length; i++)
                    EntranceItem(
                      index: i,
                      child: Column(
                        children: [
                          if (i > 0)
                            const Divider(
                              indent: AppTheme.space4,
                              endIndent: AppTheme.space4,
                            ),
                          ListTile(
                            leading: FileIconTile(
                              icon: iconForFile(p.basename(files[i].path)),
                              background: context.palette.mintSoft,
                              color: context.palette.mint,
                            ),
                            title: Text(
                              p.basename(files[i].path),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(formatBytes(files[i].lengthSync())),
                            trailing: Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                              color: context.palette.textMuted,
                            ),
                            // A received file you cannot open has not really
                            // arrived. This was a list of names and nothing
                            // else.
                            onTap: () => openFromUi(context, files[i].path),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space3),
            // Knowing the folder is the difference between "it worked" and
            // "where did it go?".
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: context.palette.textMuted,
                ),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: SelectableText(
                    transfer.inboxDirectory().path,
                    style: context.type.bodySmall,
                  ),
                ),
                // Desktop only. A folder is something a file manager opens,
                // and the phones have no reliable intent for one — Android
                // will happily accept the request and open nothing.
                if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                  Tooltip(
                    message: 'Open folder',
                    child: InkWell(
                      onTap: () =>
                          openFromUi(context, transfer.inboxDirectory().path),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.folder_open_rounded,
                          size: 14,
                          color: context.palette.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.space8,
        horizontal: AppTheme.space6,
      ),
      child: Column(
        children: [
          PulseRings(color: palette.accent, size: 84),
          const SizedBox(height: AppTheme.space5),
          Text('Looking for devices…', style: context.type.titleMedium),
          const SizedBox(height: AppTheme.space2),
          Text(
            'Open this app on the other device, on the same Wi-Fi. Or skip it '
            'and use the web address on the Share tab.',
            textAlign: TextAlign.center,
            style: context.type.bodySmall,
          ),
        ],
      ),
    );
  }
}
