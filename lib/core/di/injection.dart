import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shuttle/features/appearance/data/data_sources/appearance_local_data_source.dart';
import 'package:shuttle/features/appearance/data/repositories/appearance_repository_impl.dart';
import 'package:shuttle/features/appearance/domain/repositories/appearance_repository.dart';
import 'package:shuttle/features/appearance/domain/use_case/appearance_use_case.dart';
import 'package:shuttle/features/appearance/presentation/bloc/appearance_cubit.dart';
import 'package:shuttle/features/discovery/data/data_sources/mdns_data_source.dart';
import 'package:shuttle/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:shuttle/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:shuttle/features/discovery/domain/use_case/discovery_use_case.dart';
import 'package:shuttle/features/discovery/presentation/bloc/discovery_cubit.dart';
import 'package:shuttle/features/history/data/data_sources/history_local_data_source.dart';
import 'package:shuttle/features/history/data/repositories/history_repository_impl.dart';
import 'package:shuttle/features/history/domain/repositories/history_repository.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/history/presentation/bloc/history_cubit.dart';
import 'package:shuttle/features/identity/data/data_sources/identity_local_data_source.dart';
import 'package:shuttle/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:shuttle/features/identity/domain/repositories/identity_repository.dart';
import 'package:shuttle/features/identity/domain/use_case/identity_use_case.dart';
import 'package:shuttle/features/identity/presentation/bloc/identity_cubit.dart';
import 'package:shuttle/features/sharing/data/data_sources/http_server_data_source.dart';
import 'package:shuttle/features/sharing/data/repositories/sharing_repository_impl.dart';
import 'package:shuttle/features/sharing/domain/repositories/sharing_repository.dart';
import 'package:shuttle/features/sharing/domain/use_case/sharing_use_case.dart';
import 'package:shuttle/features/sharing/presentation/bloc/sharing_bloc.dart';
import 'package:shuttle/features/transfer/data/data_sources/http_transfer_data_source.dart';
import 'package:shuttle/features/transfer/data/repositories/transfer_repository_impl.dart';
import 'package:shuttle/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:shuttle/features/transfer/domain/use_case/transfer_use_case.dart';
import 'package:shuttle/features/transfer/presentation/bloc/peer_files_cubit.dart';
import 'package:shuttle/features/usb/data/data_sources/adb_data_source.dart';
import 'package:shuttle/features/usb/data/data_sources/mtp_data_source.dart';
import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:shuttle/features/usb/data/repositories/usb_repository_impl.dart';
import 'package:shuttle/features/usb/domain/repositories/usb_repository.dart';
import 'package:shuttle/features/usb/domain/use_case/usb_use_case.dart';
import 'package:shuttle/features/usb/presentation/bloc/usb_cubit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final GetIt sl = GetIt.instance;

/// Wires the app together.
///
/// The rule this encodes: **data sources, repositories and use cases are
/// singletons; blocs and cubits are factories.**
///
/// A running HTTP server, an mDNS registration and a transfer log have to
/// outlive any screen, so they are registered once. State holders must not —
/// a singleton bloc ties a server's lifetime to a widget's, keeps emitting
/// into closed screens, and lets any part of the app reach in and mutate
/// another screen's state. Every `registerFactory` below hands out a fresh
/// instance to whichever page asked, and that page disposes it.
Future<void> configureDependencies() async {
  // ── Platform paths ────────────────────────────────────────────────────
  final support = await getApplicationSupportDirectory();
  final inbox = await _inboxDirectory();
  await _migrateLegacyInbox(inbox);

  // ── History (registered first: three features record into it) ─────────
  sl
    ..registerLazySingleton<HistoryLocalDataSource>(
      () => HistoryLocalDataSourceImpl(
        File(p.join(support.path, 'transfer_history.json')),
      ),
    )
    ..registerLazySingleton<HistoryRepository>(
      () => HistoryRepositoryImpl(sl()),
    )
    ..registerLazySingleton(() => HistoryUseCase(sl()))
    ..registerFactory(() => HistoryCubit(sl()));

  // ── Appearance ────────────────────────────────────────────────────────
  sl
    ..registerLazySingleton<AppearanceLocalDataSource>(
      () => AppearanceLocalDataSourceImpl(
        File(p.join(support.path, 'appearance.json')),
      ),
    )
    ..registerLazySingleton<AppearanceRepository>(
      () => AppearanceRepositoryImpl(sl()),
    )
    ..registerLazySingleton(() => AppearanceUseCase(sl()))
    ..registerFactory(() => AppearanceCubit(sl()));

  // ── Identity ──────────────────────────────────────────────────────────
  sl
    ..registerLazySingleton<IdentityLocalDataSource>(
      () => IdentityLocalDataSourceImpl(
        File(p.join(support.path, 'device_identity.json')),
      ),
    )
    ..registerLazySingleton<IdentityRepository>(
      () => IdentityRepositoryImpl(sl()),
    )
    ..registerLazySingleton(() => IdentityUseCase(sl()))
    ..registerFactory(() => IdentityCubit(sl()));

  // ── Sharing ───────────────────────────────────────────────────────────
  sl
    ..registerLazySingleton(
      () => HttpServerDataSource(
        inboxDirectory: inbox,
        // Read at request time, so renaming the device updates the page
        // without restarting the server.
        deviceName: () => sl<IdentityUseCase>().current().name,
      ),
    )
    ..registerLazySingleton<SharingRepository>(
      () => SharingRepositoryImpl(sl(), sl()),
    )
    ..registerLazySingleton(() => SharingUseCase(sl()))
    ..registerFactory(() => SharingBloc(sl()));

  // ── Discovery ─────────────────────────────────────────────────────────
  sl
    ..registerLazySingleton(MdnsDataSource.new)
    ..registerLazySingleton<DiscoveryRepository>(
      () => DiscoveryRepositoryImpl(sl()),
    )
    ..registerLazySingleton(() => DiscoveryUseCase(sl()))
    ..registerFactory(() => DiscoveryCubit(sl()));

  // ── Transfer ──────────────────────────────────────────────────────────
  sl
    ..registerLazySingleton(
      () => HttpTransferDataSource(
        Dio(
          BaseOptions(
            // A peer that has left the network should fail in seconds, not
            // hang the button. Deliberately no receive timeout: a big file
            // over slow Wi-Fi is not a stuck request.
            connectTimeout: const Duration(seconds: 8),
            // On every request, so the device at the other end can log a peer
            // as "Wi-Fi" rather than as a browser.
            headers: {HttpTransferDataSource.clientHeader: '1'},
          ),
        ),
      ),
    )
    ..registerLazySingleton<TransferRepository>(
      () =>
          TransferRepositoryImpl(dataSource: sl(), inbox: inbox, history: sl()),
    )
    ..registerLazySingleton(() => TransferUseCase(sl()))
    // Takes the peer it is for, so each peer screen gets its own.
    ..registerFactoryParam<PeerFilesCubit, String, int>(
      (host, port) => PeerFilesCubit(sl(), sl(), host: host, port: port),
    );

  // ── USB ───────────────────────────────────────────────────────────────
  sl
    ..registerLazySingleton<List<UsbBackend>>(
      // adb first: where both are possible it is faster and gives real
      // folders instead of MTP's flat walk.
      () => [AdbBackend(), MtpBackend()],
    )
    ..registerLazySingleton<UsbRepository>(
      () => UsbRepositoryImpl(backends: sl(), inbox: inbox, history: sl()),
    )
    ..registerLazySingleton(() => UsbUseCase(sl()))
    ..registerFactory(() => UsbCubit(sl()));
}

/// The folder received files land in, named the same on every platform so the
/// answer to "where did it go" is one sentence.
const String inboxFolderName = 'Shuttle';

/// Where received files land.
///
/// The rule is that a file must be findable *without* this app. A transfer
/// that completes into a folder only the app can read has not really arrived —
/// it cannot be opened, attached to a message, or seen from a computer, and
/// the person is left looking at a list of files they cannot touch. That is
/// exactly what the previous version did on Android: it wrote to
/// `getApplicationDocumentsDirectory()`, which is `/data/user/0/<pkg>/…`,
/// private to the app and invisible to every file manager on the device.
///
/// So the candidates are tried in order of how findable the result is, and the
/// first one that genuinely accepts a write wins. Probing rather than
/// switching on the OS version is deliberate: what shared storage allows has
/// changed with almost every Android release, and a vendor can be stricter
/// still. Asking the filesystem is the only answer that cannot be out of date.
Future<Directory> _inboxDirectory() async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(p.join(downloads.path, inboxFolderName));
    }
  }

  if (Platform.isAndroid) {
    final candidates = <Directory>[
      // The real Downloads folder — what a file manager opens first, and
      // where anyone would think to look.
      Directory(p.join('/storage/emulated/0/Download', inboxFolderName)),
      // Failing that, the app's own folder on the shared volume. Not in
      // Downloads, but still on storage a cable can reach.
      ...?await getExternalStorageDirectories(type: StorageDirectory.downloads),
    ];

    for (final candidate in candidates) {
      if (await _isWritable(candidate)) {
        debugPrint('Inbox: ${candidate.path}');
        return candidate;
      }
    }
  }

  // iOS lands here, and it is the right answer there: with
  // `UIFileSharingEnabled` set, this folder is what the Files app shows under
  // "On My iPhone".
  final documents = await getApplicationDocumentsDirectory();
  return Directory(p.join(documents.path, inboxFolderName));
}

/// Moves anything left behind in the old inbox into the new one.
///
/// Received files used to go to `<app documents>/Received`, which on a phone
/// only this app could read. Moving the destination without moving the files
/// would have looked like data loss: they would stop appearing in the Received
/// list, and the folder they were still sitting in is one the person has no
/// way to open.
///
/// Best-effort by design. A file that will not move is left where it is rather
/// than failing the launch, and a name already taken in the new folder is left
/// alone rather than overwritten.
Future<void> _migrateLegacyInbox(Directory inbox) async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    final legacy = Directory(p.join(documents.path, 'Received'));
    if (!legacy.existsSync() || legacy.path == inbox.path) return;

    await inbox.create(recursive: true);
    for (final file in legacy.listSync().whereType<File>()) {
      final target = File(p.join(inbox.path, p.basename(file.path)));
      if (target.existsSync()) continue;
      try {
        await file.rename(target.path);
      } on FileSystemException {
        // Across volumes — the app's private storage and the shared one are
        // not always the same mount — a rename cannot work, so copy instead.
        await file.copy(target.path);
        await file.delete();
      }
    }

    if (legacy.listSync().isEmpty) await legacy.delete();
  } catch (e) {
    debugPrint('Could not migrate the old inbox: $e');
  }
}

/// Whether a directory can be created *and* written to.
///
/// Creating it is not proof of anything. Android will happily report a
/// directory as created and then refuse every write into it, so the only
/// honest test is to put a byte there and take it back out again.
Future<bool> _isWritable(Directory directory) async {
  try {
    await directory.create(recursive: true);
    final probe = File(p.join(directory.path, '.write_probe'));
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } catch (e) {
    debugPrint('Inbox candidate rejected — ${directory.path}: $e');
    return false;
  }
}
