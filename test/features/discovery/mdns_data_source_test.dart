import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/discovery/data/data_sources/mdns_data_source.dart';
import 'package:nsd/nsd.dart';

/// What a browse result turns into.
///
/// The plugin's own discovery is not exercised here — that is Bonjour's job,
/// and there is nothing to test in a method channel. What the app decides
/// afterwards is what has actually been wrong: which services are this device,
/// which are duplicates of one device, and which cannot be dialled at all.
void main() {
  Service service({
    required String name,
    String? id,
    int? port = 53317,
    String? address,
    bool resolved = true,
  }) => Service(
    name: name,
    type: MdnsDataSource.serviceType,
    port: port,
    // Bonjour gives a `.local` name before it gives an address, and both are
    // dialable. `resolved: false` is the state before either arrives.
    host: resolved ? '$name.local' : null,
    addresses: address == null ? null : [InternetAddress(address)],
    txt: id == null ? null : {'id': Uint8List.fromList(utf8.encode(id))},
  );

  test('this device is not one of its own peers', () {
    final peers = MdnsDataSource.peersFrom([
      service(name: 'MacBookPro', id: 'me', address: '192.168.1.5'),
      service(name: 'iPhone', id: 'them', address: '192.168.1.9'),
    ], 'me');

    expect(peers.map((p) => p.name), ['iPhone']);
  });

  test('a rename is filtered on id, not on the name it is showing', () {
    // Two devices that happen to share a display name used to hide each
    // other, because self-filtering compared names.
    final peers = MdnsDataSource.peersFrom([
      service(name: 'iPhone', id: 'me', address: '192.168.1.5'),
      service(name: 'iPhone', id: 'them', address: '192.168.1.9'),
    ], 'me');

    expect(peers, hasLength(1));
    expect(peers.single.id, 'them');
  });

  test('one device advertised twice is one row', () {
    // Bonjour suffixes a clashing instance rather than replacing it, so a
    // device that re-registers without unregistering shows up as both.
    final peers = MdnsDataSource.peersFrom([
      service(name: 'iPhone', id: 'same', address: '192.168.1.9'),
      service(name: 'iPhone (2)', id: 'same', address: '192.168.1.9'),
    ], 'me');

    expect(peers, hasLength(1));
  });

  test('the resolved registration wins over the one still resolving', () {
    // Order matters here: the unusable one is seen first, so keeping it would
    // be the natural mistake.
    final peers = MdnsDataSource.peersFrom([
      service(name: 'iPhone', id: 'same', resolved: false),
      service(name: 'iPhone (2)', id: 'same', address: '192.168.1.9'),
    ], 'me');

    expect(peers.single.host, '192.168.1.9');
    expect(peers.single.isReachable, isTrue);
  });

  test('a service with no port is not offered as tappable', () {
    final peers = MdnsDataSource.peersFrom([
      service(name: 'iPhone', id: 'them', port: null),
    ], 'me');

    expect(peers, isEmpty);
  });

  test('a Bonjour hostname is enough to dial, before any address', () {
    final peers = MdnsDataSource.peersFrom([
      service(name: 'iPhone', id: 'them'),
    ], 'me');

    expect(peers.single.host, 'iPhone.local');
    expect(peers.single.isReachable, isTrue);
  });

  test('a peer with nowhere to dial keeps its place but is not tappable', () {
    // Bonjour has the service but not yet where it lives. The row shows,
    // disabled, rather than offering a tap that would fail.
    final peers = MdnsDataSource.peersFrom([
      service(name: 'iPhone', id: 'them', resolved: false),
    ], 'me');

    expect(peers.single.host, isNull);
    expect(peers.single.isReachable, isFalse);
  });

  test('something else on the network without our id still lists', () {
    // An id is how peers are told apart, but its absence is not a reason to
    // hide a service that is otherwise dialable.
    final peers = MdnsDataSource.peersFrom([
      service(name: 'Stranger', address: '192.168.1.20'),
    ], 'me');

    expect(peers.single.name, 'Stranger');
    expect(peers.single.id, 'Stranger');
  });
}
