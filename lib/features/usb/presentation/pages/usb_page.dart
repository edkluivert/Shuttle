import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/core/di/injection.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/utils/formatters.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:shuttle/core/widgets/selection_bar.dart';
import 'package:shuttle/core/widgets/transfer_progress_bar.dart';
import 'package:shuttle/features/sharing/presentation/pages/share_page.dart'
    show iconForFile;
import 'package:shuttle/features/usb/domain/entities/usb_entities.dart';
import 'package:shuttle/features/usb/presentation/bloc/usb_cubit.dart';

/// Browsing a phone that is plugged in — no Wi-Fi, no app on the other end.
class UsbPage extends StatelessWidget {
  const UsbPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!UsbCubit.isSupportedPlatform) {
      return const EmptyState(
        icon: Icons.usb_off_rounded,
        title: 'Use the computer for this',
        body:
            'A phone cannot read another device over USB — it is never the '
            'host end of the cable. Open this on your Mac instead, or use the '
            'Share tab to move files over the network.',
      );
    }

    return BlocProvider(
      create: (_) => sl<UsbCubit>()..probe(),
      child: const _UsbView(),
    );
  }
}

class _UsbView extends StatelessWidget {
  const _UsbView();

  Future<void> _sendFiles(BuildContext context) async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    final paths = result?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty || !context.mounted) return;

    await context.read<UsbCubit>().push(paths.map(File.new).toList());
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsbCubit>();

    return BlocConsumer<UsbCubit, UsbState>(
      listenWhen: (previous, current) => current.message != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(state.message!)));
        cubit.messageShown();
      },
      builder: (context, state) {
        if (state.scanning && state.device == null) {
          return _scanning(context, state);
        }
        if (state.device == null) return _noDevice(context, state, cubit);

        return Column(
          children: [
            _PathBar(state: state),
            if (state.progress != null)
              TransferProgressBar(
                progress: state.progress!,
                onCancel: cubit.cancel,
              ),
            Expanded(child: _fileList(context, state, cubit)),
            if (state.isSelecting)
              SelectionBar(
                count: state.selectedFiles.length,
                totalBytes: state.selectedBytes,
                actionLabel: 'Copy',
                busy: state.busy,
                onAction: cubit.pullSelected,
                onClear: cubit.clearSelection,
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space4,
                  AppTheme.space2,
                  AppTheme.space4,
                  AppTheme.space4,
                ),
                child: OutlinedButton.icon(
                  onPressed: state.busy ? null : () => _sendFiles(context),
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Send files to phone'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _scanning(BuildContext context, UsbState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseRings(color: context.palette.accent, size: 84),
            const SizedBox(height: AppTheme.space5),
            Text('Reading the phone', style: context.type.titleMedium),
            if (state.scanNote != null) ...[
              const SizedBox(height: AppTheme.space2),
              Text(
                state.scanNote!,
                textAlign: TextAlign.center,
                style: context.type.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fileList(BuildContext context, UsbState state, UsbCubit cubit) {
    if (state.entries.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Empty folder',
        body: 'Nothing here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space2,
        AppTheme.space4,
        AppTheme.space4,
      ),
      itemCount: state.entries.length,
      itemBuilder: (context, index) {
        final entry = state.entries[index];

        return EntranceItem(
          index: index,
          child: _EntryTile(
            entry: entry,
            selected: state.selected.contains(entry.path),
            // Once a selection exists, tapping any file adds to it rather
            // than doing something different — file-manager convention.
            selecting: state.isSelecting,
            onTap: () {
              if (entry.isDirectory) {
                if (!state.isSelecting) cubit.open(entry);
                return;
              }
              if (state.isSelecting) {
                cubit.toggle(entry);
              } else {
                cubit.pullOne(entry);
              }
            },
            onLongPress: entry.isDirectory ? null : () => cubit.toggle(entry),
          ),
        );
      },
    );
  }

  Widget _noDevice(BuildContext context, UsbState state, UsbCubit cubit) {
    // The automatic scan only runs the backends that answer in a moment, so a
    // phone reachable *only* over MTP looks like no phone at all here. Say so
    // — otherwise the picker below is the one thing nobody thinks to open.
    final slowAvailable = cubit.backends.any(
      (b) => !b.scansQuickly && !state.unavailable.contains(b),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space4,
        AppTheme.space4,
        AppTheme.space8,
      ),
      children: [
        SurfaceCard(
          child: EmptyState(
            icon: Icons.usb_rounded,
            title: 'No phone detected',
            body: slowAvailable
                ? 'Plug the phone in and unlock it. If its USB mode is set to '
                      'charging only, switch it to file transfer. Without USB '
                      'debugging turned on, pick MTP under Connection below — '
                      'it is not tried automatically because it has to read '
                      'the whole phone first.'
                : 'Plug the phone in and unlock it. If its USB mode is set to '
                      'charging only, switch it to file transfer.',
            action: FilledButton.icon(
              onPressed: state.scanning ? null : cubit.scan,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Look again'),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.space6),
        const SectionLabel('Connection'),
        SurfaceCard(
          child: ListTile(
            leading: FileIconTile(
              icon: Icons.settings_ethernet_rounded,
              background: context.palette.accentSoft,
              color: context.palette.accent,
            ),
            title: const Text('How to connect'),
            subtitle: Text(state.preferredBackend ?? 'Automatic'),
            trailing: const _BackendMenu(),
          ),
        ),
        if (state.unavailable.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space6),
          const SectionLabel('Not set up yet'),
          SurfaceCard(
            child: Column(
              children: [
                for (var i = 0; i < state.unavailable.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      indent: AppTheme.space4,
                      endIndent: AppTheme.space4,
                    ),
                  ListTile(
                    leading: FileIconTile(
                      icon: Icons.info_outline_rounded,
                      background: context.palette.surfaceHigh,
                    ),
                    title: Text(state.unavailable[i].name),
                    subtitle: Text(state.unavailable[i].setupHint),
                    isThreeLine: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.selected,
    required this.selecting,
    required this.onTap,
    this.onLongPress,
  });

  final UsbEntry entry;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: selected ? palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: selected
              ? palette.accent.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: selecting && !entry.isDirectory
            ? SizedBox(
                width: 40,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onLongPress?.call(),
                ),
              )
            : FileIconTile(
                icon: entry.isDirectory
                    ? Icons.folder_rounded
                    : iconForFile(entry.name),
                background: entry.isDirectory ? palette.accentSoft : null,
                color: entry.isDirectory ? palette.accent : null,
              ),
        title: Text(entry.name, overflow: TextOverflow.ellipsis),
        // A negative size means the backend could not tell us. Better no
        // subtitle than a confident "0 B".
        subtitle: entry.isDirectory || entry.size < 0
            ? null
            : Text(formatBytes(entry.size)),
        trailing: entry.isDirectory
            ? Icon(Icons.chevron_right_rounded, color: palette.textMuted)
            : selecting
            ? null
            : IconButton(
                icon: const Icon(Icons.download_rounded, size: 18),
                tooltip: 'Copy to this computer',
                onPressed: onTap,
              ),
      ),
    );
  }
}

class _PathBar extends StatelessWidget {
  const _PathBar({required this.state});

  final UsbState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cubit = context.read<UsbCubit>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        0,
        AppTheme.space4,
        AppTheme.space2,
      ),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space2,
          vertical: AppTheme.space2,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              tooltip: 'Up one folder',
              onPressed: state.canGoUp ? cubit.goUp : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          state.device?.label ?? 'Phone',
                          style: context.type.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space2),
                      StatusPill(
                        label: sl<UsbCubit>().backends.isEmpty
                            ? ''
                            : (context
                                      .read<UsbCubit>()
                                      .state
                                      .preferredBackend ??
                                  'Auto'),
                        tone: StatusTone.live,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.currentPath.isEmpty ? '/' : state.currentPath,
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const _BackendMenu(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Refresh',
              onPressed: state.busy ? null : cubit.refresh,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets you force MTP on a phone that adb would otherwise claim.
class _BackendMenu extends StatelessWidget {
  const _BackendMenu();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsbCubit>();
    final preferred = context.select((UsbCubit c) => c.state.preferredBackend);

    return PopupMenuButton<String?>(
      tooltip: 'How to connect',
      icon: const Icon(Icons.tune_rounded, size: 18),
      onSelected: cubit.usePreferred,
      itemBuilder: (context) => [
        CheckedPopupMenuItem<String?>(
          checked: preferred == null,
          child: const Text('Automatic'),
        ),
        for (final backend in cubit.backends)
          CheckedPopupMenuItem<String?>(
            value: backend.name,
            checked: preferred == backend.name,
            child: Text(backend.name),
          ),
      ],
    );
  }
}
