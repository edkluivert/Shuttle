import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/sharing/data/data_sources/web_page.dart';
import 'package:path/path.dart' as p;

/// A file that arrived over HTTP, or was taken.
///
/// [fromApp] separates the two kinds of caller this server has: another copy
/// of this app, which announces itself with a header, and a plain browser,
/// which does not. They read differently in the log, and the per-device
/// activity list only means anything if a peer's transfers are attributable.
typedef ServedFile = ({
  String name,
  int bytes,
  String peer,
  bool incoming,
  bool fromApp,
  String path,
});

/// The HTTP side of this device.
///
///   GET  /                → a page any browser can use, so the other end
///                           needs nothing installed
///   GET  /api/files       → what is on offer, as JSON
///   GET  /download/<i>    → the i-th file
///   PUT  /upload?name=x   → a file being sent to this device
///
/// Knows nothing about entities, repositories or the log — it serves bytes
/// and reports what moved.
class HttpServerDataSource {
  HttpServerDataSource({
    required this.inboxDirectory,
    required this.deviceName,
  });

  /// Set by the app's own HTTP client on every request; never by a browser.
  /// Mirrors `HttpTransferDataSource.clientHeader`, spelled out here rather
  /// than imported so the server does not depend on the transfer feature.
  static const String clientHeader = 'x-shuttle';

  /// Tried first, so the address is predictable.
  ///
  /// This is what makes a USB cable usable: over USB there is no network, so
  /// the only ways across are tethering or an `adb forward`, and `adb
  /// forward` needs a port you can name in advance.
  static const int preferredPort = 53317;

  final Directory inboxDirectory;

  /// Read at request time via the callback so a rename shows up on the page
  /// without restarting the server.
  final String Function() deviceName;

  HttpServer? _server;
  Future<void>? _starting;
  final List<File> _shared = [];
  List<String> _addresses = const [];

  final StreamController<ServedFile> _transfers =
      StreamController<ServedFile>.broadcast();

  /// Every completed transfer, for whoever is keeping the log.
  Stream<ServedFile> get transfers => _transfers.stream;

  int? get port => _server?.port;
  bool get isRunning => _server != null;
  List<String> get addresses => _addresses;
  List<File> get sharedFiles => List.unmodifiable(_shared);

  /// Idempotent, including against a caller that arrives while the last one
  /// is still binding.
  ///
  /// Two callers race at launch — the shell sends `SharingStarted` and the
  /// home page calls this before advertising — and the `_server != null`
  /// guard alone does not stop them: both read it as null before either has
  /// finished binding. They then each bound a socket, one overwrote the
  /// other's field, and both called `listen` on whichever survived, which
  /// threw "Stream was already listened to" and leaked a bound port 53317
  /// that nothing was ever going to answer on. Handing the second caller the
  /// first one's future serialises them.
  Future<void> start() {
    if (_server != null) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    try {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, preferredPort);
      } on SocketException {
        // Taken — usually by another copy of this app on the same machine.
        // Any port beats refusing to start.
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      _addresses = await _localAddresses();
      _server!.listen(
        _handle,
        // Without this a single malformed request would kill the whole
        // server, and the app would go on claiming it was sharing.
        onError: (Object e) => debugPrint('Request error: $e'),
      );
    } catch (e) {
      debugPrint('Failed to start HTTP server: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _addresses = const [];
  }

  /// Returns whether anything was actually added — the same file picked twice
  /// is a no-op rather than a duplicate row.
  bool share(Iterable<File> files) {
    var added = false;
    for (final file in files) {
      if (_shared.any((f) => f.path == file.path)) continue;
      _shared.add(file);
      added = true;
    }
    return added;
  }

  void unshareAt(int index) {
    if (index < 0 || index >= _shared.length) return;
    _shared.removeAt(index);
  }

  void unshareAll() => _shared.clear();

  // ── Request handling ──────────────────────────────────────────────────

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
        // Opened on the machine serving it, the page is nonsense: half of it
        // offers to send this device's files to itself. That is an easy
        // mistake to make — you copy the address to check it works and paste
        // it into the browser already in front of you.
        return _sendHtml(
          request,
          buildWebPage(
            deviceName(),
            viewedFromSelf: _isSelf(request),
            addresses: _addresses,
            port: port,
          ),
        );
      }
      if (request.method == 'GET' && path == '/api/files') {
        return _sendJson(request, _fileListJson());
      }
      if (request.method == 'GET' && path.startsWith('/download/')) {
        return _sendFile(request, path.substring('/download/'.length));
      }
      if (request.method == 'PUT' && path == '/upload') {
        return _receiveUpload(request);
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      debugPrint('Unhandled request error: $e');
      await _tryClose(request.response);
    }
  }

  List<Map<String, dynamic>> _fileListJson() => _shared
      .map(
        (f) => {
          'name': p.basename(f.path),
          'size': f.existsSync() ? f.lengthSync() : 0,
        },
      )
      .toList(growable: false);

  Future<void> _sendHtml(HttpRequest request, String html) async {
    request.response
      ..headers.contentType = ContentType.html
      ..write(html);
    await request.response.close();
  }

  Future<void> _sendJson(HttpRequest request, Object payload) async {
    request.response
      ..headers.contentType = ContentType.json
      // The browser page polls this; a cached answer would leave it showing
      // files that are no longer shared.
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      // jsonEncode, not string interpolation: a file named `my "best" take.mov`
      // used to produce a body the other device could not parse.
      ..write(jsonEncode(payload));
    await request.response.close();
  }

  Future<void> _sendFile(HttpRequest request, String rawIndex) async {
    final index = int.tryParse(rawIndex);
    if (index == null || index < 0 || index >= _shared.length) {
      request.response.statusCode = HttpStatus.notFound;
      return request.response.close();
    }

    final file = _shared[index];
    // Picked an hour ago, moved since: better a clean 404 than a half-written
    // response the receiver saves as a truncated file.
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return request.response.close();
    }

    final name = p.basename(file.path);
    request.response.headers
      ..contentType = _contentTypeFor(name)
      ..contentLength = file.lengthSync()
      ..set(HttpHeaders.contentDisposition, _contentDisposition(name));

    try {
      await file.openRead().pipe(request.response);
      _transfers.add((
        name: name,
        bytes: file.lengthSync(),
        peer: _peerOf(request),
        incoming: false,
        fromApp: _isApp(request),
        // The file that was taken is still here — this end shared it, it did
        // not lose it.
        path: file.path,
      ));
    } catch (e) {
      // The receiver walking away mid-transfer is routine, not an error worth
      // tearing anything down for.
      debugPrint('Transfer of $name ended early: $e');
    }
  }

  Future<void> _receiveUpload(HttpRequest request) async {
    final requested = request.uri.queryParameters['name'] ?? 'upload';
    final target = _uniqueInboxFile(_safeName(requested));

    IOSink? sink;
    try {
      await inboxDirectory.create(recursive: true);
      sink = target.openWrite();
      await sink.addStream(request);
      await sink.close();
      sink = null;

      _transfers.add((
        name: p.basename(target.path),
        bytes: target.existsSync() ? target.lengthSync() : 0,
        peer: _peerOf(request),
        incoming: true,
        fromApp: _isApp(request),
        path: target.path,
      ));

      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    } catch (e) {
      debugPrint('Upload failed: $e');
      await sink?.close();
      // A partial file looks like a real one in the receive list.
      if (target.existsSync()) {
        try {
          await target.delete();
        } catch (_) {}
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await _tryClose(request.response);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// The address the request came from — the only identity a plain browser
  /// has, and enough to tell one device from another on a home network.
  static String _peerOf(HttpRequest request) =>
      request.connectionInfo?.remoteAddress.address ?? 'unknown';

  /// Whether this request came from another copy of the app rather than from
  /// a browser.
  static bool _isApp(HttpRequest request) =>
      request.headers.value(clientHeader) != null;

  /// Whether this request came from the machine running the server.
  ///
  /// Loopback covers `localhost`; the address list covers typing this
  /// device's own LAN address into its own browser.
  bool _isSelf(HttpRequest request) {
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null) return false;
    return remote.isLoopback || _addresses.contains(remote.address);
  }

  /// Strips any directory part a caller might send. `../../.ssh/id_rsa` as a
  /// filename must land in the inbox as `id_rsa`, not walk out of it.
  static String _safeName(String requested) {
    final base = p.basename(requested.replaceAll(r'\', '/')).trim();
    if (base.isEmpty || base == '.' || base == '..') return 'upload';
    return base;
  }

  /// `photo.jpg`, `photo (1).jpg`, … — receiving two files with one name
  /// should not silently lose the first.
  File _uniqueInboxFile(String name) {
    var candidate = File(p.join(inboxDirectory.path, name));
    if (!candidate.existsSync()) return candidate;

    final stem = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 1; i < 1000; i++) {
      candidate = File(p.join(inboxDirectory.path, '$stem ($i)$ext'));
      if (!candidate.existsSync()) return candidate;
    }
    return candidate;
  }

  /// Both spellings: the plain one for old clients, and the RFC 5987 one that
  /// survives non-ASCII, so `Fotos für Ana.zip` keeps its name.
  static String _contentDisposition(String name) {
    final ascii = name
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '_')
        .replaceAll('"', '');
    final encoded = Uri.encodeComponent(name);
    return 'attachment; filename="$ascii"; filename*=UTF-8\'\'$encoded';
  }

  /// Enough to make browsers preview the obvious things instead of treating
  /// every file as a binary blob.
  static ContentType _contentTypeFor(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return ContentType('image', 'jpeg');
      case '.png':
        return ContentType('image', 'png');
      case '.gif':
        return ContentType('image', 'gif');
      case '.heic':
        return ContentType('image', 'heic');
      case '.webp':
        return ContentType('image', 'webp');
      case '.mp4':
      case '.m4v':
        return ContentType('video', 'mp4');
      case '.mov':
        return ContentType('video', 'quicktime');
      case '.mp3':
        return ContentType('audio', 'mpeg');
      case '.pdf':
        return ContentType('application', 'pdf');
      case '.txt':
      case '.md':
        return ContentType('text', 'plain', charset: 'utf-8');
      case '.json':
        return ContentType('application', 'json');
      case '.zip':
        return ContentType('application', 'zip');
      default:
        return ContentType('application', 'octet-stream');
    }
  }

  /// Every non-loopback IPv4 this device answers on. Wi-Fi usually comes
  /// first; a USB tether shows up here too, which is what makes a cabled
  /// connection work with no extra code.
  static Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return interfaces
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((a) => !a.startsWith('169.254.')) // self-assigned
          .toList(growable: false);
    } catch (e) {
      debugPrint('Could not list network interfaces: $e');
      return const [];
    }
  }

  Future<void> _tryClose(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {
      // Already closed, or the socket is gone.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _transfers.close();
  }
}
