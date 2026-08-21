import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/sharing/data/data_sources/http_server_data_source.dart';
import 'package:path/path.dart' as p;

/// The server is the contract between the two devices — and between the phone
/// and any browser — so it is exercised over a real socket rather than by
/// calling the handlers directly.
void main() {
  late Directory temp;
  late Directory inbox;
  late HttpServerDataSource server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lft_test');
    inbox = Directory(p.join(temp.path, 'inbox'));
    server = HttpServerDataSource(
      inboxDirectory: inbox,
      deviceName: () => 'Test Device',
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<HttpClientResponse> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url(path));
      return await request.close();
    } finally {
      client.close();
    }
  }

  File writeFile(String name, String contents) {
    final file = File(p.join(temp.path, name))..writeAsStringSync(contents);
    return file;
  }

  test('starts on a real port and reports at least one address', () {
    expect(server.isRunning, isTrue);
    expect(server.port, isNotNull);
  });

  test('two callers starting at once bind one server', () async {
    // What actually happens at launch: the shell sends SharingStarted and the
    // home page calls start() before advertising. Both used to get past the
    // "already running" guard, bind a socket each, and then listen twice on
    // the survivor — "Stream was already listened to", with a bound port left
    // behind that answered nothing.
    final fresh = HttpServerDataSource(
      inboxDirectory: inbox,
      deviceName: () => 'Test Device',
    );
    addTearDown(fresh.stop);

    await Future.wait([fresh.start(), fresh.start(), fresh.start()]);

    expect(fresh.isRunning, isTrue);
    // The proof it is the *listening* socket and not an orphan: it answers.
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${fresh.port}/api/files'),
      )).close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    } finally {
      client.close();
    }
  });

  test('lists shared files as JSON', () async {
    server.share([writeFile('notes.txt', 'hello')]);

    final response = await get('/api/files');
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;

    expect(response.statusCode, 200);
    expect(list, hasLength(1));
    expect((list.first as Map)['name'], 'notes.txt');
    expect((list.first as Map)['size'], 5);
  });

  test('a quote in a filename does not break the listing', () async {
    // The old handler built this JSON by string interpolation, so this name
    // produced a body the other device could not parse.
    server.share([writeFile('my "best" take.txt', 'x')]);

    final response = await get('/api/files');
    final list = jsonDecode(await response.transform(utf8.decoder).join())
        as List<dynamic>;

    expect((list.first as Map)['name'], 'my "best" take.txt');
  });

  test('serves the file bytes with a filename the browser can use', () async {
    server.share([writeFile('report.pdf', 'PDF-ish bytes')]);

    final response = await get('/download/0');
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, 200);
    expect(body, 'PDF-ish bytes');
    expect(response.headers.value('content-disposition'), contains('report.pdf'));
    expect(response.headers.contentType?.mimeType, 'application/pdf');
  });

  test('a non-ASCII filename survives the round trip', () async {
    server.share([writeFile('Fotos für Ana.txt', 'x')]);

    final response = await get('/download/0');
    await response.drain<void>();

    // The plain filename is ASCII-safe for old clients; the RFC 5987 copy is
    // what carries the real name.
    expect(
      response.headers.value('content-disposition'),
      contains("filename*=UTF-8''"),
    );
    expect(
      response.headers.value('content-disposition'),
      contains(Uri.encodeComponent('Fotos für Ana.txt')),
    );
  });

  test('an index nobody is sharing is a 404, not a crash', () async {
    final response = await get('/download/7');
    await response.drain<void>();
    expect(response.statusCode, 404);
  });

  test('a file deleted after it was shared 404s instead of half-sending',
      () async {
    final file = writeFile('gone.txt', 'here for now');
    server.share([file]);
    file.deleteSync();

    final response = await get('/download/0');
    await response.drain<void>();
    expect(response.statusCode, 404);
  });

  test('unsharing removes it from the listing', () async {
    server.share([writeFile('a.txt', 'a'), writeFile('b.txt', 'b')]);
    server.unshareAt(0);

    final list = jsonDecode(
      await (await get('/api/files')).transform(utf8.decoder).join(),
    ) as List<dynamic>;

    expect(list, hasLength(1));
    expect((list.first as Map)['name'], 'b.txt');
  });

  test('the same file added twice is only shared once', () {
    final file = writeFile('once.txt', 'x');
    expect(server.share([file]), isTrue);
    expect(server.share([file]), isFalse, reason: 'nothing new to add');
    expect(server.sharedFiles, hasLength(1));
  });

  group('receiving an upload', () {
    Future<HttpClientResponse> put(String name, String body) async {
      final client = HttpClient();
      try {
        final request = await client.putUrl(
          url('/upload?name=${Uri.encodeComponent(name)}'),
        );
        request.add(utf8.encode(body));
        return await request.close();
      } finally {
        client.close();
      }
    }

    test('writes the body into the inbox', () async {
      final response = await put('photo.jpg', 'jpeg bytes');
      await response.drain<void>();

      expect(response.statusCode, 200);
      final saved = File(p.join(inbox.path, 'photo.jpg'));
      expect(saved.existsSync(), isTrue);
      expect(saved.readAsStringSync(), 'jpeg bytes');
    });

    test('a second file with the same name does not overwrite the first',
        () async {
      await (await put('photo.jpg', 'first')).drain<void>();
      await (await put('photo.jpg', 'second')).drain<void>();

      expect(
        File(p.join(inbox.path, 'photo.jpg')).readAsStringSync(),
        'first',
      );
      expect(
        File(p.join(inbox.path, 'photo (1).jpg')).readAsStringSync(),
        'second',
      );
    });

    test('a path in the filename cannot escape the inbox', () async {
      // `PUT /upload?name=../../secrets.txt` must land in the inbox as
      // `secrets.txt`, not one directory up.
      await (await put('../../secrets.txt', 'nope')).drain<void>();

      expect(File(p.join(inbox.path, 'secrets.txt')).existsSync(), isTrue);
      expect(
        File(p.join(inbox.parent.parent.path, 'secrets.txt')).existsSync(),
        isFalse,
      );
    });
  });

  group('telling a peer from a browser', () {
    Future<ServedFile> nextTransfer(Future<void> Function() act) async {
      final served = server.transfers.first;
      await act();
      return served.timeout(const Duration(seconds: 5));
    }

    Future<void> put(String name, {bool asApp = false}) async {
      final client = HttpClient();
      try {
        final request = await client.putUrl(url('/upload?name=$name'));
        if (asApp) {
          request.headers.set(HttpServerDataSource.clientHeader, '1');
        }
        request.add(utf8.encode('bytes'));
        await (await request.close()).drain<void>();
      } finally {
        client.close();
      }
    }

    test('an upload with no header reads as a browser', () async {
      final served = await nextTransfer(() => put('from-browser.txt'));

      expect(served.incoming, isTrue);
      expect(served.fromApp, isFalse);
    });

    test('the app announces itself on an upload', () async {
      final served = await nextTransfer(
        () => put('from-peer.txt', asApp: true),
      );

      expect(served.incoming, isTrue);
      expect(served.fromApp, isTrue);
    });

    test('the log gets the local path of what was uploaded', () async {
      // Without this the Received row is a name and nothing else — there is
      // no file for a tap to open.
      final served = await nextTransfer(() => put('landed.txt'));

      expect(served.path, p.join(inbox.path, 'landed.txt'));
      expect(File(served.path).existsSync(), isTrue);
    });

    test('a download carries the same distinction', () async {
      server.share([writeFile('notes.txt', 'hello')]);

      final served = await nextTransfer(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(url('/download/0'));
          request.headers.set(HttpServerDataSource.clientHeader, '1');
          await (await request.close()).drain<void>();
        } finally {
          client.close();
        }
      });

      expect(served.incoming, isFalse, reason: 'the peer took a file');
      expect(served.fromApp, isTrue);
      // A file this device handed out is still here; the row should open it.
      expect(File(served.path).existsSync(), isTrue);
    });
  });

  test('serves a browser page at the root', () async {
    final response = await get('/');
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/html');
    expect(body, contains('Test Device'));
  });

  test('anything else is a 404', () async {
    final response = await get('/../etc/passwd');
    await response.drain<void>();
    expect(response.statusCode, 404);
  });
}
