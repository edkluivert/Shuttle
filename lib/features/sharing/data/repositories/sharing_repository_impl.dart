import 'dart:async';
import 'dart:io';

import 'package:shuttle/core/utils/current_and_changes.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/sharing/data/data_sources/http_server_data_source.dart';
import 'package:shuttle/features/sharing/domain/entities/server_status.dart';
import 'package:shuttle/features/sharing/domain/entities/shared_file.dart';
import 'package:shuttle/features/sharing/domain/repositories/sharing_repository.dart';

/// Turns the raw server into domain state, and files what it serves into the
/// transfer log.
///
/// A singleton — the server has to keep running while the user moves between
/// screens — but the bloc reading it is not, which is the whole point of the
/// split.
class SharingRepositoryImpl implements SharingRepository {
  SharingRepositoryImpl(this._dataSource, this._history) {
    // The server reports what it served; the log is written here rather than
    // inside the data source, which has no business knowing there is one.
    _transfers = _dataSource.transfers.listen((served) {
      _history.record(
        name: served.name,
        bytes: served.bytes,
        peer: served.peer,
        incoming: served.incoming,
        // A peer announces itself with a header; a browser cannot. Logging
        // both as "Browser" made a phone running this app indistinguishable
        // from someone who had typed the address in.
        way: served.fromApp ? TransferWay.network : TransferWay.browser,
        path: served.path,
      );
      // An upload changes nothing about the share list, but the Receive
      // screen is watching this to know something arrived.
      _emit();
    });
  }

  final HttpServerDataSource _dataSource;
  final HistoryUseCase _history;

  final StreamController<ServerStatus> _controller =
      StreamController<ServerStatus>.broadcast();
  StreamSubscription<ServedFile>? _transfers;

  @override
  ServerStatus get status => ServerStatus(
    isRunning: _dataSource.isRunning,
    port: _dataSource.port,
    addresses: _dataSource.addresses,
    files: _dataSource.sharedFiles.map(SharedFile.fromFile).toList(),
  );

  @override
  Stream<ServerStatus> watch() =>
      currentAndChanges(() => status, _controller.stream);

  void _emit() => _controller.add(status);

  @override
  Future<void> start() async {
    await _dataSource.start();
    _emit();
  }

  @override
  Future<void> stop() async {
    await _dataSource.stop();
    _emit();
  }

  @override
  void share(Iterable<File> files) {
    if (_dataSource.share(files)) _emit();
  }

  @override
  void unshareAt(int index) {
    _dataSource.unshareAt(index);
    _emit();
  }

  @override
  void unshareAll() {
    _dataSource.unshareAll();
    _emit();
  }

  Future<void> dispose() async {
    await _transfers?.cancel();
    await _dataSource.dispose();
    await _controller.close();
  }
}
