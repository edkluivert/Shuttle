import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/history/data/data_sources/history_local_data_source.dart';
import 'package:shuttle/features/history/data/repositories/history_repository_impl.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:path/path.dart' as p;

/// The log's whole point is surviving a quit, so these write it, drop it, and
/// read it back rather than checking an in-memory list.
void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lft_history');
    file = File(p.join(temp.path, 'history.json'));
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// The save is debounced so a batch writes once; tests have to outwait it.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 800));

  test('a fresh log is empty', () {
    expect(HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file))).current(), isEmpty);
  });

  test('survives being reopened', () async {
    HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file))).record(
      name: 'photo.jpg',
      bytes: 2048,
      peer: '192.168.1.20',
      incoming: true,
      way: TransferWay.browser,
    );
    await settle();

    final reopened = HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)));
    expect(reopened.current(), hasLength(1));
    expect(reopened.current().single.name, 'photo.jpg');
    expect(reopened.current().single.bytes, 2048);
    expect(reopened.current().single.peer, '192.168.1.20');
    expect(reopened.current().single.incoming, isTrue);
    expect(reopened.current().single.way, TransferWay.browser);
  });

  test('remembers which way each file went', () async {
    final history = HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)))
      ..record(
        name: 'in.txt',
        bytes: 1,
        peer: 'a',
        incoming: true,
        way: TransferWay.usb,
      )
      ..record(
        name: 'out.txt',
        bytes: 2,
        peer: 'b',
        incoming: false,
        way: TransferWay.network,
      );

    expect(history.current().where((e) => e.incoming).length, 1);
    expect(history.current().where((e) => !e.incoming).length, 1);
    expect(history.current().fold<int>(0, (s, e) => s + e.bytes), 3);
    await settle();
  });

  test('newest first', () async {
    final history = HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)))
      ..record(
        name: 'first',
        bytes: 1,
        peer: 'a',
        incoming: true,
        way: TransferWay.usb,
      )
      ..record(
        name: 'second',
        bytes: 1,
        peer: 'a',
        incoming: true,
        way: TransferWay.usb,
      );

    expect(history.current().first.name, 'second');
    await settle();
  });

  test('recent() takes from the top without disturbing the log', () async {
    final history = HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)));
    for (var i = 0; i < 10; i++) {
      history.record(
        name: 'file$i',
        bytes: 1,
        peer: 'a',
        incoming: true,
        way: TransferWay.usb,
      );
    }

    expect(history.current().take(3).map((e) => e.name), ['file9', 'file8', 'file7']);
    expect(history.current(), hasLength(10));
    await settle();
  });

  test('clearing empties the file too, not just the list', () async {
    final history = HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)))
      ..record(
        name: 'a',
        bytes: 1,
        peer: 'a',
        incoming: true,
        way: TransferWay.usb,
      );
    await settle();

    await history.clear();

    expect(HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file))).current(), isEmpty);
  });

  test('a corrupt file reads as empty rather than failing to launch', () {
    file.writeAsStringSync('{not json at all');
    expect(HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file))).current(), isEmpty);
  });

  test('entries written by a newer version are skipped, not fatal', () {
    // Anything unreadable in the list is dropped; the rest still loads.
    file.writeAsStringSync(jsonEncode([
      'a bare string where an object should be',
      {
        'name': 'good.txt',
        'bytes': 5,
        'peer': 'a',
        'incoming': true,
        'way': 'usb',
        'at': DateTime(2026).toIso8601String(),
      },
    ]));

    final history = HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)));
    expect(history.current(), hasLength(1));
    expect(history.current().single.name, 'good.txt');
  });

  test('an unknown transfer method falls back rather than throwing', () {
    file.writeAsStringSync(jsonEncode([
      {
        'name': 'x',
        'bytes': 1,
        'peer': 'a',
        'incoming': false,
        'way': 'carrier-pigeon',
        'at': DateTime(2026).toIso8601String(),
      },
    ]));

    expect(HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file))).current().single.way, TransferWay.browser);
  });

  group('opening what a row refers to', () {
    late Directory files;

    setUp(() async {
      files = await Directory.systemTemp.createTemp('lft_files');
    });

    tearDown(() {
      if (files.existsSync()) files.deleteSync(recursive: true);
    });

    test('the local path survives a restart', () async {
      final saved = File(p.join(files.path, 'photo.jpg'))
        ..writeAsStringSync('jpeg');

      HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)))
          .record(
        name: 'photo.jpg',
        bytes: 4,
        peer: '192.168.1.20',
        incoming: true,
        way: TransferWay.network,
        path: saved.path,
      );
      await settle();

      final reopened =
          HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)))
              .current()
              .single;
      expect(reopened.path, saved.path);
      expect(reopened.existsLocally, isTrue);
    });

    test('a file deleted since the transfer is not offered', () async {
      final saved = File(p.join(files.path, 'gone.jpg'))..writeAsStringSync('x');

      final history =
          HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)));
      await history.record(
        name: 'gone.jpg',
        bytes: 1,
        peer: '192.168.1.20',
        incoming: true,
        way: TransferWay.network,
        path: saved.path,
      );
      expect(history.current().single.existsLocally, isTrue);

      saved.deleteSync();
      expect(
        history.current().single.existsLocally,
        isFalse,
        reason: 'checked against the disk, not remembered from the transfer',
      );
    });

    test('an entry from before paths were logged still reads', () async {
      // The upgrade case: a log written by the previous version has no path
      // key at all. It must load, and simply not offer to open anything.
      file.writeAsStringSync(jsonEncode([
        {
          'name': 'old.jpg',
          'bytes': 10,
          'peer': '192.168.1.20',
          'incoming': true,
          'way': 'browser',
          'at': DateTime.now().toIso8601String(),
        },
      ]));

      final event =
          HistoryUseCase(HistoryRepositoryImpl(HistoryLocalDataSourceImpl(file)))
              .current()
              .single;
      expect(event.name, 'old.jpg');
      expect(event.path, isNull);
      expect(event.existsLocally, isFalse);
    });
  });

  group('how an entry reads', () {
    test('groups by calendar day', () {
      final event = TransferEvent(
        name: 'a',
        bytes: 1,
        peer: 'a',
        incoming: true,
        at: DateTime(2026, 8, 11, 23, 45),
      );
      expect(event.day, DateTime(2026, 8, 11));
    });

    test('says how long ago in words', () {
      TransferEvent ago(Duration d) => TransferEvent(
            name: 'a',
            bytes: 1,
            peer: 'a',
            incoming: true,
            at: DateTime.now().subtract(d),
          );

      expect(ago(const Duration(seconds: 5)).whenLabel, 'just now');
      expect(ago(const Duration(minutes: 5)).whenLabel, '5 min ago');
      expect(ago(const Duration(hours: 3)).whenLabel, '3 h ago');
      expect(ago(const Duration(days: 1)).whenLabel, 'yesterday');
      expect(ago(const Duration(days: 4)).whenLabel, '4 d ago');
    });
  });
}
