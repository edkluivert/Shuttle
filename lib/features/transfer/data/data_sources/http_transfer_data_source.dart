import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Talking to another device's server over HTTP.
class HttpTransferDataSource {
  HttpTransferDataSource(this._dio);

  /// Marks a request as coming from the app rather than from a browser.
  ///
  /// The receiving server logs the two differently — "Wi-Fi" for a peer, and
  /// "Browser" for someone typing the address in — and the header is the only
  /// thing that tells them apart. A browser simply never sends it, so old
  /// clients and old servers both keep working.
  static const String clientHeader = 'x-shuttle';

  final Dio _dio;
  CancelToken? _cancelToken;

  Future<List<Map<String, dynamic>>?> listFiles(String host, int port) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        _url(host, port, '/api/files'),
      );
      return (response.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (e) {
      debugPrint('Could not list files on $host:$port — $e');
      return null;
    }
  }

  /// Writes to [savePath]. Throws on failure, including cancellation, which
  /// the repository tells apart.
  Future<void> download({
    required String host,
    required int port,
    required int index,
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) async {
    _cancelToken = CancelToken();
    await _dio.download(
      _url(host, port, '/download/$index'),
      savePath,
      cancelToken: _cancelToken,
      onReceiveProgress: onProgress,
    );
    _cancelToken = null;
  }

  /// Pushes a file to the peer's inbox. Throws on failure, cancellation
  /// included.
  ///
  /// This is the same `PUT /upload` the browser page uses — the receiving end
  /// needed no new code to accept it.
  Future<void> upload({
    required String host,
    required int port,
    required File file,
    required void Function(int sent, int total) onProgress,
  }) async {
    _cancelToken = CancelToken();
    // Streamed from disk rather than read into memory, so sending a 4 GB video
    // costs no more RAM than sending a photo. dio cannot work the length out
    // from a stream, and without it the request goes out chunked and the
    // receiver has no total to show a bar against.
    final length = await file.length();

    await _dio.put<void>(
      _url(host, port, '/upload'),
      data: file.openRead(),
      queryParameters: {'name': p.basename(file.path)},
      options: Options(
        headers: {Headers.contentLengthHeader: length},
        contentType: Headers.textPlainContentType,
      ),
      onSendProgress: onProgress,
      cancelToken: _cancelToken,
    );
    _cancelToken = null;
  }

  void cancel() => _cancelToken?.cancel('cancelled by user');

  static bool isCancellation(Object error) =>
      error is DioException && CancelToken.isCancel(error);

  String _url(String host, int port, String path) {
    // A bare IPv6 address has to be bracketed or the URL is unparseable.
    final authority = host.contains(':') ? '[$host]' : host;
    return 'http://$authority:$port$path';
  }

  void dispose() {
    _cancelToken?.cancel('disposed');
    _dio.close(force: true);
  }
}
