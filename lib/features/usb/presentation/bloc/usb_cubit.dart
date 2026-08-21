import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:shuttle/features/usb/domain/use_case/usb_use_case.dart';

class UsbState extends Equatable {
  const UsbState({
    this.scanning = false,
    this.busy = false,
    this.device,
    this.entries = const [],
    this.breadcrumbs = const [],
    this.selected = const {},
    this.progress,
    this.message,
    this.scanNote,
    this.preferredBackend,
    this.unavailable = const [],
  });

  final bool scanning;
  final bool busy;
  final UsbDevice? device;
  final List<UsbEntry> entries;

  /// The path stack. The first entry is the device root.
  final List<String> breadcrumbs;

  /// Selected file ids. Held by id rather than by index so the selection
  /// survives a refresh that reorders the list.
  final Set<String> selected;

  final TransferProgress? progress;
  final String? message;

  /// Shown under the spinner. MTP walks the whole device before it can show
  /// one folder, which takes minutes — silence there reads as a hang.
  final String? scanNote;

  final String? preferredBackend;
  final List<UsbBackend> unavailable;

  String get currentPath =>
      breadcrumbs.isEmpty ? (device?.rootPath ?? '/') : breadcrumbs.last;

  bool get canGoUp => breadcrumbs.length > 1;
  bool get isSelecting => selected.isNotEmpty;

  List<UsbEntry> get files =>
      entries.where((e) => !e.isDirectory).toList(growable: false);

  List<UsbEntry> get selectedFiles =>
      files.where((e) => selected.contains(e.path)).toList(growable: false);

  int get selectedBytes =>
      selectedFiles.where((e) => e.size > 0).fold(0, (s, e) => s + e.size);

  UsbState copyWith({
    bool? scanning,
    bool? busy,
    UsbDevice? device,
    bool clearDevice = false,
    List<UsbEntry>? entries,
    List<String>? breadcrumbs,
    Set<String>? selected,
    TransferProgress? progress,
    bool clearProgress = false,
    String? message,
    bool clearMessage = false,
    String? scanNote,
    bool clearScanNote = false,
    String? preferredBackend,
    bool clearPreferred = false,
    List<UsbBackend>? unavailable,
  }) => UsbState(
    scanning: scanning ?? this.scanning,
    busy: busy ?? this.busy,
    device: clearDevice ? null : (device ?? this.device),
    entries: entries ?? this.entries,
    breadcrumbs: breadcrumbs ?? this.breadcrumbs,
    selected: selected ?? this.selected,
    progress: clearProgress ? null : (progress ?? this.progress),
    message: clearMessage ? null : (message ?? this.message),
    scanNote: clearScanNote ? null : (scanNote ?? this.scanNote),
    preferredBackend: clearPreferred
        ? null
        : (preferredBackend ?? this.preferredBackend),
    unavailable: unavailable ?? this.unavailable,
  );

  @override
  List<Object?> get props => [
    scanning,
    busy,
    device,
    entries,
    breadcrumbs,
    selected,
    progress,
    message,
    scanNote,
    preferredBackend,
    unavailable,
  ];
}

/// The USB tab's state. Created by that page; the backends and the device
/// handle live in the repository.
class UsbCubit extends Cubit<UsbState> {
  UsbCubit(this._useCase) : super(const UsbState());

  final UsbUseCase _useCase;

  /// adb lists a device in well under a second. MTP is never scanned
  /// automatically — it walks the entire device, which is minutes.
  static const String fastBackend = 'Android (adb)';

  /// Only a computer can drive the cable: the desktop end is the USB host,
  /// and a phone can never host another phone.
  static bool get isSupportedPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  bool _cancelRequested = false;

  List<UsbBackend> get backends => _useCase.backends();

  Future<void> probe() async {
    final availability = await _useCase.probeBackends();
    if (isClosed) return;

    emit(
      state.copyWith(
        unavailable: _useCase
            .backends()
            .where((b) => availability[b.name] != true)
            .toList(growable: false),
      ),
    );

    if (availability[fastBackend] == true && state.device == null) {
      await scan();
    }
  }

  Future<void> scan() async {
    if (state.scanning) return;

    final preferred = state.preferredBackend;
    final slow = preferred != null && preferred != fastBackend;
    emit(
      state.copyWith(
        scanning: true,
        clearMessage: true,
        scanNote: slow
            ? 'Reading the whole phone. MTP cannot list one folder at a time, '
                  'so this first pass takes several minutes — after it, '
                  'browsing is instant.'
            : null,
      ),
    );

    final device = await _useCase.scan(preferredBackend: preferred);
    if (isClosed) return;

    if (device == null) {
      emit(
        state.copyWith(
          scanning: false,
          clearDevice: true,
          entries: const [],
          breadcrumbs: const [],
          clearScanNote: true,
        ),
      );
      return;
    }

    final List<UsbEntry> entries;
    try {
      entries = await _useCase.list(device, device.rootPath);
    } on UsbDeviceGone catch (gone) {
      // The phone answered the scan and was gone by the listing — every
      // libmtp tool opens its own session, and Android drops to charging-only
      // on its own. Back to the no-device screen with the reason, rather than
      // a browser claiming the phone is empty.
      if (isClosed) return;
      emit(
        state.copyWith(
          scanning: false,
          clearDevice: true,
          entries: const [],
          breadcrumbs: const [],
          clearScanNote: true,
          message: gone.message,
        ),
      );
      return;
    }
    if (isClosed) return;

    // MTP cannot name the phone without reading it, so the device it hands
    // back before the listing is a placeholder. Now there is a real name.
    final label = _useCase.activeBackend()?.discoveredLabel;
    emit(
      state.copyWith(
        scanning: false,
        device: label == null
            ? device
            : UsbDevice(
                id: device.id,
                label: label,
                rootPath: device.rootPath,
              ),
        entries: entries,
        breadcrumbs: [device.rootPath],
        clearScanNote: true,
      ),
    );
  }

  Future<void> usePreferred(String? backendName) async {
    if (state.preferredBackend == backendName) return;
    emit(
      UsbState(preferredBackend: backendName, unavailable: state.unavailable),
    );
    await scan();
  }

  Future<void> open(UsbEntry entry) async {
    final device = state.device;
    if (device == null || !entry.isDirectory) return;

    final entries = await _list(device, entry.path);
    if (entries == null || isClosed) return;

    emit(
      state.copyWith(
        entries: entries,
        breadcrumbs: [...state.breadcrumbs, entry.path],
      ),
    );
  }

  Future<void> goUp() async {
    if (!state.canGoUp) return;
    final device = state.device;
    if (device == null) return;

    final breadcrumbs = [...state.breadcrumbs]..removeLast();
    final entries = await _list(device, breadcrumbs.last);
    if (entries == null || isClosed) return;

    emit(state.copyWith(entries: entries, breadcrumbs: breadcrumbs));
  }

  Future<void> refresh() async {
    final device = state.device;
    if (device == null) return;

    final entries = await _list(device, state.currentPath);
    if (entries == null || isClosed) return;
    emit(state.copyWith(entries: entries));
  }

  /// Null when the phone dropped off: the screen keeps whatever folder it was
  /// showing and says what happened, instead of turning into an empty one.
  Future<List<UsbEntry>?> _list(UsbDevice device, String path) async {
    try {
      return await _useCase.list(device, path);
    } on UsbDeviceGone catch (gone) {
      if (!isClosed) emit(state.copyWith(message: gone.message));
      return null;
    }
  }

  void toggle(UsbEntry entry) {
    final selected = Set<String>.from(state.selected);
    if (!selected.remove(entry.path)) selected.add(entry.path);
    emit(state.copyWith(selected: selected));
  }

  void clearSelection() => emit(state.copyWith(selected: const {}));

  void messageShown() => emit(state.copyWith(clearMessage: true));

  Future<void> pullSelected() => _pull(state.selectedFiles);

  Future<void> pullOne(UsbEntry entry) => _pull([entry]);

  Future<void> _pull(List<UsbEntry> entries) async {
    final device = state.device;
    if (device == null || state.busy || entries.isEmpty) return;

    _cancelRequested = false;
    emit(state.copyWith(busy: true, selected: const {}));

    final saved = await _useCase.pull(
      device: device,
      entries: entries,
      isCancelled: () => _cancelRequested,
      onProgress: (progress) {
        if (!isClosed) emit(state.copyWith(progress: progress));
      },
    );
    if (isClosed) return;

    emit(
      state.copyWith(
        busy: false,
        clearProgress: true,
        message: _summary(saved, entries.length),
      ),
    );
  }

  Future<void> push(List<File> files) async {
    final device = state.device;
    if (device == null || state.busy || files.isEmpty) return;

    emit(state.copyWith(busy: true));
    var sent = 0;
    for (final file in files) {
      final ok = await _useCase.push(
        device: device,
        file: file,
        remoteDirectory: state.currentPath,
      );
      if (ok) sent++;
    }
    if (isClosed) return;

    emit(state.copyWith(busy: false, message: 'Sent $sent to ${device.label}'));
    await refresh();
  }

  /// Stops after the file in flight — the helper tools own the copy itself,
  /// and killing one mid-write would leave a truncated file behind.
  void cancel() {
    if (!state.busy) return;
    _cancelRequested = true;
    emit(state.copyWith(message: 'Stopping after this file…'));
  }

  static String _summary(int saved, int requested) {
    if (saved == 0) return 'Could not copy anything';
    if (saved == requested) {
      return requested == 1 ? 'Saved 1 file' : 'Saved $requested files';
    }
    return 'Saved $saved of $requested — the rest failed';
  }
}
