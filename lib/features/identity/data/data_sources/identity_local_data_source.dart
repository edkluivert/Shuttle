import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/identity/domain/entities/device_identity.dart';

abstract interface class IdentityLocalDataSource {
  DeviceIdentity read();

  Future<void> write(DeviceIdentity identity);
}

class IdentityLocalDataSourceImpl implements IdentityLocalDataSource {
  IdentityLocalDataSourceImpl(this.file);

  final File file;

  @override
  DeviceIdentity read() {
    try {
      if (file.existsSync()) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final id = json['id']?.toString();
        final name = json['name']?.toString();
        if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
          return DeviceIdentity(id: id, name: name);
        }
      }
    } catch (e) {
      // A corrupt file is not worth failing to launch over — a fresh identity
      // is generated below and overwrites it.
      debugPrint('Could not read saved identity: $e');
    }

    return DeviceIdentity(id: _randomId(), name: defaultName());
  }

  @override
  Future<void> write(DeviceIdentity identity) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'id': identity.id, 'name': identity.name}),
      );
    } catch (e) {
      debugPrint('Could not save identity: $e');
    }
  }

  /// The machine's own name where the OS will tell us ("Ada's MacBook Pro"),
  /// since that is what the person at the other end is looking for.
  @visibleForTesting
  static String defaultName() {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final host = Platform.localHostname.replaceAll('.local', '').trim();
      if (host.isNotEmpty) return host;
    }
    if (Platform.isAndroid) return 'Android phone';
    if (Platform.isIOS) return 'iPhone';
    return 'My device';
  }

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
