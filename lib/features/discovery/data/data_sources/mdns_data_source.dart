import 'dart:async';
import 'dart:convert';

import 'package:shuttle/core/utils/current_and_changes.dart';
import 'package:flutter/foundation.dart';
import 'package:shuttle/features/discovery/domain/entities/peer.dart';
import 'package:nsd/nsd.dart';

/// Bonjour/mDNS: announcing this device, and browsing for others.
class MdnsDataSource {
  static const String serviceType = '_shuttle._tcp';

  /// The TXT key carrying the device id. Self-filtering used to compare
  /// display names, so two devices that happened to share one hid each other;
  /// an id cannot collide and survives a rename.
  static const String _idKey = 'id';

  Registration? _registration;
  Discovery? _discovery;
  String? _selfId;
  Object? _lastError;

  final StreamController<List<Peer>> _peers =
      StreamController<List<Peer>>.broadcast();

  List<Peer> _current = const [];

  Object? get lastError => _lastError;

  Stream<List<Peer>> get peers =>
      currentAndChanges(() => _current, _peers.stream);

  Future<void> advertise({
    required String deviceId,
    required String deviceName,
    required int port,
  }) async {
    _selfId = deviceId;
    try {
      await _unregister();
      _registration = await register(
        Service(
          name: deviceName,
          type: serviceType,
          port: port,
          txt: {_idKey: Uint8List.fromList(utf8.encode(deviceId))},
        ),
      );
    } catch (e) {
      _lastError = e;
      debugPrint('Failed to register service: $e');
    }
  }

  Future<void> startSearching() async {
    if (_discovery != null) return;
    try {
      _discovery = await startDiscovery(
        serviceType,
        // Bonjour hands back a `.local` hostname, which resolves on Apple
        // platforms but not reliably on Android. Asking for addresses up
        // front means every peer arrives with an IP we can actually dial.
        ipLookupType: IpLookupType.v4,
      );
      _discovery!.addListener(_onServicesChanged);
      _onServicesChanged();
    } catch (e) {
      _lastError = e;
      debugPrint('Failed to start discovery: $e');
      _peers.add(_current);
    }
  }

  Future<void> refresh() async {
    await _stopDiscovery();
    _lastError = null;
    await startSearching();
  }

  void _onServicesChanged() {
    final discovery = _discovery;
    if (discovery == null) return;

    _current = peersFrom(discovery.services, _selfId);

    _lastError = null;
    _peers.add(_current);
  }

  /// The peer list a browse result reduces to: this device removed, anything
  /// unusable dropped, and one row per device.
  ///
  /// Bonjour renames a clashing instance rather than replacing it, so a device
  /// that re-registers without unregistering first — after a rename, or a
  /// restart nothing cleaned up behind — is advertised twice, as "iPhone" and
  /// "iPhone (2)". Both carry the same id, and listing both asks the user to
  /// guess which of two identical devices is the real one.
  ///
  /// Note what this cannot fix: a registration left behind by an app that was
  /// killed keeps a *different* id if its storage was wiped in between, which
  /// is a routine thing during development. That is a genuinely separate
  /// device as far as anything here can tell, and it stays listed until the
  /// record expires.
  @visibleForTesting
  static List<Peer> peersFrom(Iterable<Service> services, String? selfId) {
    final byId = <String, Peer>{};

    for (final service in services) {
      if (_idOf(service) == selfId) continue;
      if (service.port == null) continue;

      final peer = Peer(
        id: _idOf(service) ?? service.name ?? 'unknown',
        name: service.name ?? 'Unknown device',
        host: _hostOf(service),
        port: service.port,
      );

      // A registration that resolved to an address beats one that has not:
      // only the first can actually be dialled.
      final existing = byId[peer.id];
      if (existing == null || (!existing.isReachable && peer.isReachable)) {
        byId[peer.id] = peer;
      }
    }

    return byId.values.toList(growable: false);
  }

  /// The device id a peer advertised, or null for anything not from this app.
  static String? _idOf(Service service) {
    final raw = service.txt?[_idKey];
    if (raw == null) return null;
    try {
      return utf8.decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// The best address to dial: a looked-up IP when we have one, the Bonjour
  /// hostname otherwise.
  static String? _hostOf(Service service) {
    final addresses = service.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      return addresses.first.address;
    }
    return service.host;
  }

  Future<void> _unregister() async {
    final registration = _registration;
    _registration = null;
    if (registration == null) return;
    try {
      await unregister(registration);
    } catch (e) {
      debugPrint('Failed to unregister: $e');
    }
  }

  Future<void> _stopDiscovery() async {
    final discovery = _discovery;
    _discovery = null;
    _current = const [];
    if (discovery == null) return;
    try {
      discovery.removeListener(_onServicesChanged);
      await stopDiscovery(discovery);
    } catch (e) {
      debugPrint('Failed to stop discovery: $e');
    }
  }

  Future<void> stop() async {
    await _unregister();
    await _stopDiscovery();
  }

  Future<void> dispose() async {
    await stop();
    await _peers.close();
  }
}
