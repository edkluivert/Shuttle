import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/sharing/data/data_sources/http_server_data_source.dart';
import 'package:shuttle/features/transfer/data/data_sources/http_transfer_data_source.dart';
import 'package:path/path.dart' as p;

/// The two halves of a peer-to-peer transfer, run against each other.
///
/// Both ends are this app's own code, so a mock on either side would only
/// prove the mock agreed with itself. Standing up the real server and pointing
/// the real client at it is what actually tests the wire.
void main() {
  late Directory temp;
  late Directory inbox;
  late HttpServerDataSource peer;
  late HttpTransferDataSource client;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lft_transfer_test');
    inbox = Directory(p.join(temp.path, 'inbox'));
    peer = HttpServerDataSource(
      inboxDirectory: inbox,
      deviceName: () => 'The Other Device',
    );
    await peer.start();

    client = HttpTransferDataSource(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          headers: {HttpTransferDataSource.clientHeader: '1'},
        ),
      ),
    );
  });

  tearDown(() async {
    client.dispose();
    await peer.stop();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  File writeFile(String name, String contents) =>
      File(p.join(temp.path, name))..writeAsStringSync(contents);

  Future<void> send(File file) => client.upload(
    host: '127.0.0.1',
    port: peer.port!,
    file: file,
    onProgress: (_, _) {},
  );

  test('a pushed file lands in the peer inbox', () async {
    await send(writeFile('holiday.txt', 'sand and sea'));

    final landed = File(p.join(inbox.path, 'holiday.txt'));
    expect(landed.existsSync(), isTrue);
    expect(landed.readAsStringSync(), 'sand and sea');
  });

  test('the receiver logs it as a peer, not as a browser', () async {
    final served = peer.transfers.first;
    await send(writeFile('notes.txt', 'x'));

    final event = await served.timeout(const Duration(seconds: 5));
    expect(event.fromApp, isTrue);
    expect(event.incoming, isTrue);
    expect(event.name, 'notes.txt');
  });

  test('progress is reported against a real total', () async {
    // A stream body with no content length goes out chunked, and the receiver
    // has no total to draw a bar against — so the length is set explicitly and
    // this is what proves it survived.
    final samples = <({int sent, int total})>[];
    await client.upload(
      host: '127.0.0.1',
      port: peer.port!,
      file: writeFile('big.txt', 'y' * 200000),
      onProgress: (sent, total) => samples.add((sent: sent, total: total)),
    );

    expect(samples, isNotEmpty);
    expect(samples.every((s) => s.total == 200000), isTrue);
    expect(samples.last.sent, 200000);
  });

  test('a name with spaces and accents survives the trip', () async {
    await send(writeFile('Fotos für Ana.txt', 'hallo'));

    expect(File(p.join(inbox.path, 'Fotos für Ana.txt')).existsSync(), isTrue);
  });

  test('two files with one name do not collide on the receiver', () async {
    await send(writeFile('photo.txt', 'first'));
    File(p.join(temp.path, 'photo.txt')).writeAsStringSync('second');
    await send(File(p.join(temp.path, 'photo.txt')));

    expect(File(p.join(inbox.path, 'photo.txt')).readAsStringSync(), 'first');
    expect(
      File(p.join(inbox.path, 'photo (1).txt')).readAsStringSync(),
      'second',
    );
  });

  test('listing a peer that is not there fails rather than hanging', () async {
    // Port 1 is never a peer. `listFiles` swallows the error and answers null,
    // which is what lets the screen say "could not be reached" instead of
    // showing an empty share list.
    final files = await client.listFiles('127.0.0.1', 1);

    expect(files, isNull);
  });

  test('sending to a device that has left throws', () async {
    // The port has to be read before the server releases it — the repository
    // is holding an address it captured earlier, which is exactly the case
    // being tested.
    final port = peer.port!;
    await peer.stop();

    await expectLater(
      client.upload(
        host: '127.0.0.1',
        port: port,
        file: writeFile('lost.txt', 'nobody home'),
        onProgress: (_, _) {},
      ),
      throwsA(isA<DioException>()),
    );
  });
}
