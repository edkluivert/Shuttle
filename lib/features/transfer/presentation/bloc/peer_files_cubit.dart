import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/transfer/domain/entities/remote_file.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';
import 'package:shuttle/features/transfer/domain/use_case/transfer_use_case.dart';

enum PeerFilesStatus { loading, ready, unreachable }

class PeerFilesState extends Equatable {
  const PeerFilesState({
    this.status = PeerFilesStatus.loading,
    this.files = const [],
    this.activity = const [],
    this.selected = const {},
    this.progress,
    this.sending = false,
    this.message,
  });

  final PeerFilesStatus status;
  final List<RemoteFile> files;

  /// Everything that has moved between this device and this peer, newest
  /// first — both directions, from the shared transfer log.
  final List<TransferEvent> activity;

  /// Positions into [files] — the download URL addresses them by index.
  final Set<int> selected;

  final TransferProgress? progress;

  /// Which way the transfer in flight is going, so the bar can say so.
  final bool sending;

  /// One-shot text for a snackbar; cleared once shown.
  final String? message;

  bool get isConnected => status == PeerFilesStatus.ready;
  bool get isBusy => progress != null;
  bool get isSelecting => selected.isNotEmpty;
  bool get allSelected => files.isNotEmpty && selected.length == files.length;

  int get selectedBytes => selected
      .where((i) => i < files.length)
      .fold(0, (s, i) => s + files[i].size);

  PeerFilesState copyWith({
    PeerFilesStatus? status,
    List<RemoteFile>? files,
    List<TransferEvent>? activity,
    Set<int>? selected,
    TransferProgress? progress,
    bool clearProgress = false,
    bool? sending,
    String? message,
    bool clearMessage = false,
  }) => PeerFilesState(
    status: status ?? this.status,
    files: files ?? this.files,
    activity: activity ?? this.activity,
    selected: selected ?? this.selected,
    progress: clearProgress ? null : (progress ?? this.progress),
    sending: sending ?? this.sending,
    message: clearMessage ? null : (message ?? this.message),
  );

  @override
  List<Object?> get props => [
    status,
    files,
    activity,
    selected,
    progress,
    sending,
    message,
  ];
}

/// One peer: what it is offering, what has passed between the two devices,
/// and both directions of transfer. Created by the peer page and closed with
/// it.
class PeerFilesCubit extends Cubit<PeerFilesState> {
  PeerFilesCubit(
    this._useCase,
    this._history, {
    required this.host,
    required this.port,
  }) : super(const PeerFilesState()) {
    // The log is shared: a file this peer pushes to us is recorded by the
    // server, not by anything on this screen, so the only way to see it
    // arrive is to watch.
    _events = _history.watch().listen((events) {
      if (isClosed) return;
      emit(state.copyWith(activity: _mine(events)));
    });
  }

  final TransferUseCase _useCase;
  final HistoryUseCase _history;
  final String host;
  final int port;

  StreamSubscription<List<TransferEvent>>? _events;

  /// The log entries that belong to this peer.
  ///
  /// Matched on address, which is all either side ever knows the other by —
  /// the server records the address a request came from, and we record the
  /// address we dialled. A peer reachable on two interfaces at once (Wi-Fi
  /// and a USB tether) will file its transfers under whichever it used.
  List<TransferEvent> _mine(List<TransferEvent> events) =>
      events.where((e) => e.peer == host).toList(growable: false);

  Future<void> load() async {
    emit(state.copyWith(status: PeerFilesStatus.loading, selected: const {}));

    final result = await _useCase.listFiles(host, port);
    if (isClosed) return;

    emit(
      result.when(
        ok: (files) =>
            state.copyWith(status: PeerFilesStatus.ready, files: files),
        // Told apart deliberately: "sharing nothing" and "cannot be reached"
        // need different things from the user.
        err: (_) => state.copyWith(status: PeerFilesStatus.unreachable),
      ),
    );
  }

  void toggle(int index) {
    final selected = Set<int>.from(state.selected);
    if (!selected.remove(index)) selected.add(index);
    emit(state.copyWith(selected: selected));
  }

  void toggleAll() {
    emit(
      state.copyWith(
        selected: state.allSelected
            ? const {}
            : {for (var i = 0; i < state.files.length; i++) i},
      ),
    );
  }

  void clearSelection() => emit(state.copyWith(selected: const {}));

  void messageShown() => emit(state.copyWith(clearMessage: true));

  Future<void> downloadSelected() => _download(state.selected.toList()..sort());

  Future<void> downloadOne(int index) => _download([index]);

  Future<void> _download(List<int> indexes) async {
    if (state.isBusy || indexes.isEmpty) return;
    final files = state.files;

    emit(state.copyWith(selected: const {}, sending: false));

    final saved = await _useCase.download(
      host: host,
      port: port,
      files: [
        for (final index in indexes)
          if (index < files.length) (index: index, file: files[index]),
      ],
      onProgress: (progress) {
        if (!isClosed) emit(state.copyWith(progress: progress));
      },
    );
    if (isClosed) return;

    emit(
      state.copyWith(
        clearProgress: true,
        message: _received(saved, indexes.length),
      ),
    );
  }

  /// Pushes files to the peer's inbox.
  Future<void> send(List<File> files) async {
    if (state.isBusy || files.isEmpty) return;

    emit(state.copyWith(sending: true));

    final sent = await _useCase.send(
      host: host,
      port: port,
      files: files,
      onProgress: (progress) {
        if (!isClosed) emit(state.copyWith(progress: progress));
      },
    );
    if (isClosed) return;

    emit(
      state.copyWith(
        clearProgress: true,
        sending: false,
        message: _sentSummary(sent, files.length),
      ),
    );

    // What the peer is offering has not changed, but a failed push usually
    // means it has gone — worth finding out now rather than on the next tap.
    if (sent == 0) await load();
  }

  void cancel() => _useCase.cancel();

  @override
  Future<void> close() {
    _events?.cancel();
    return super.close();
  }

  static String _received(int saved, int requested) {
    if (saved == 0) return 'Could not download anything';
    if (saved == requested) {
      return requested == 1 ? 'Saved 1 file' : 'Saved $requested files';
    }
    return 'Saved $saved of $requested — the rest failed';
  }

  static String _sentSummary(int sent, int requested) {
    if (sent == 0) return 'Could not send anything';
    if (sent == requested) {
      return requested == 1 ? 'Sent 1 file' : 'Sent $requested files';
    }
    return 'Sent $sent of $requested — the rest failed';
  }
}
