import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/history/data/data_sources/history_local_data_source.dart';
import 'package:shuttle/features/history/data/repositories/history_repository_impl.dart';
import 'package:shuttle/features/history/domain/use_case/history_use_case.dart';
import 'package:shuttle/features/sharing/data/data_sources/http_server_data_source.dart';
import 'package:shuttle/features/sharing/data/data_sources/web_page.dart';
import 'package:shuttle/features/sharing/data/repositories/sharing_repository_impl.dart';
import 'package:path/path.dart' as p;

/// A browser can take a file or drop one off without the app saying a word.
/// These cover the record that makes those visible, and the page's promise to
/// name both ends of every transfer.
void main() {
  late Directory temp;
  late HttpServerDataSource dataSource;
  late SharingRepositoryImpl repository;
  late HistoryRepositoryImpl history;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lft_activity');
    // Real objects all the way down, on a throwaway directory: the thing
    // under test is that a served file reaches the log, and a mock in the
    // middle would be asserting on the wiring rather than the behaviour.
    history = HistoryRepositoryImpl(
      HistoryLocalDataSourceImpl(File(p.join(temp.path, 'history.json'))),
    );
    dataSource = HttpServerDataSource(
      inboxDirectory: Directory(p.join(temp.path, 'inbox')),
      deviceName: () => 'Test Mac',
    );
    repository = SharingRepositoryImpl(dataSource, HistoryUseCase(history));
    await repository.start();
  });

  tearDown(() async {
    await repository.dispose();
    await history.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// The data source reports a completed transfer on a stream, and the
  /// repository files it from a listener — both asynchronous. Asserting on
  /// the log in the same turn as the request would be racing that delivery.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${dataSource.port}$path'),
      );
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close();
    }
    await settle();
  }

  Future<void> put(String name, String body) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(
        Uri.parse(
          'http://127.0.0.1:${dataSource.port}/upload?name=$name',
        ),
      );
      request.add(utf8.encode(body));
      final response = await request.close();
      await response.drain<void>();
    } finally {
      client.close();
    }
    await settle();
  }

  group('the activity log', () {
    test('starts empty', () {
      expect(history.current, isEmpty);
    });

    test('records a download as outgoing, with who took it', () async {
      final file = File(p.join(temp.path, 'notes.txt'))
        ..writeAsStringSync('hello');
      repository.share([file]);

      await get('/download/0');

      expect(history.current, hasLength(1));
      final event = history.current.single;
      expect(event.name, 'notes.txt');
      expect(event.bytes, 5);
      expect(event.incoming, isFalse);
      expect(event.peer, '127.0.0.1');
    });

    test('records an upload as incoming', () async {
      await put('photo.jpg', 'jpeg bytes');

      expect(history.current, hasLength(1));
      final event = history.current.single;
      expect(event.name, 'photo.jpg');
      expect(event.incoming, isTrue);
      expect(event.peer, '127.0.0.1');
    });

    test('newest first, so the last thing that happened is on top', () async {
      await put('first.txt', 'a');
      await put('second.txt', 'b');

      expect(history.current.first.name, 'second.txt');
      expect(history.current.last.name, 'first.txt');
    });

    test('an upload that was renamed to avoid a clash logs its real name',
        () async {
      // The second file lands as `photo (1).jpg`; logging the requested name
      // would point at a file that is not the one that arrived.
      await put('photo.jpg', 'first');
      await put('photo.jpg', 'second');

      expect(history.current.first.name, 'photo (1).jpg');
    });

    test('clearing empties it', () async {
      await put('a.txt', 'a');
      await history.clear();
      expect(history.current, isEmpty);
    });

    test('a missing file logs nothing — it never moved', () async {
      await get('/download/9');
      expect(history.current, isEmpty);
    });
  });

  group('the browser page', () {
    test('names the device it belongs to, and the direction of each half', () {
      final html = buildWebPage('Ada Mac');

      expect(html, contains('You are connected to'));
      expect(html, contains('Download from Ada Mac'));
      expect(html, contains('Send to Ada Mac'));
    });

    test('a device name with markup renders as text, not as markup', () {
      final html = buildWebPage('<b>Mac</b>');

      expect(html, contains('&lt;b&gt;Mac&lt;/b&gt;'));
      expect(html, isNot(contains('<b>Mac</b>')));
    });

    test('a quote in the name cannot break the script', () {
      // `O'Brien's Mac` used to end the JavaScript string literal, which took
      // the whole page's behaviour down with it.
      final html = buildWebPage("O'Brien's Mac");

      expect(html, contains(r"\'Brien\'s Mac"));
    });

    test('opened on the serving device, it says so instead of offering to '
        'copy that device onto itself', () async {
      // A request from 127.0.0.1 is the machine running the server. The
      // transfer UI is meaningless there — "Send to MacBookPro" from
      // MacBookPro — so it must not be what gets rendered.
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${dataSource.port}/'),
        );
        final response = await request.close();
        final html = await response.transform(utf8.decoder).join();

        expect(html, contains('on Test Mac itself'));
        expect(html, contains('meant for your'));
        expect(html, isNot(contains('Send to Test Mac')));
      } finally {
        client.close();
      }
    });

    test('the self view hands over the address to type elsewhere', () {
      final html = buildWebPage(
        'Test Mac',
        viewedFromSelf: true,
        addresses: const ['192.168.1.20', '192.168.42.5'],
        port: 53317,
      );

      expect(html, contains('http://192.168.1.20:53317'));
      // The second network is offered as a fallback, not hidden — only one of
      // them is the one the other device is on.
      expect(html, contains('http://192.168.42.5:53317'));
    });

    test('a name containing a script tag cannot close the block', () {
      final html = buildWebPage('</script><script>alert(1)</script>');

      expect(html, contains(r'\x3C'));
      expect(html, isNot(contains('<script>alert(1)')));
    });
  });
}
