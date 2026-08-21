import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:path/path.dart' as p;

/// Talks to an Android phone through `adb`.
///
/// Preferred over MTP where it is available: it is faster, it reports real
/// errors instead of silently truncating, and on a machine with Android
/// Studio installed it is already there and already authorised. The cost is
/// that the phone needs USB debugging switched on.
class AdbBackend implements UsbBackend {
  @override
  String get name => 'Android (adb)';

  /// `adb devices` answers in well under a second.
  @override
  bool get scansQuickly => true;

  /// `adb devices` already carries the model name.
  @override
  String? get discoveredLabel => null;

  /// adb's device-level complaints, as opposed to a per-path `ls` error.
  @visibleForTesting
  static bool describesNoDevice(String stderr) {
    const markers = [
      'device offline',
      'device not found',
      'no devices/emulators found',
      'device unauthorized',
      'device still authorizing',
      'error: closed',
    ];
    final lower = stderr.toLowerCase();
    return markers.any(lower.contains);
  }

  @override
  String get setupHint =>
      'Turn on Developer options → USB debugging on the phone, then accept '
      'the prompt asking you to trust this computer.';

  /// Android Studio puts adb here but does not put it on PATH, which is why
  /// the plain lookup is not enough on a stock Mac setup.
  static final List<String> _candidatePaths = [
    'adb',
    p.join(
      Platform.environment['HOME'] ?? '',
      'Library/Android/sdk/platform-tools/adb',
    ),
    p.join(
      Platform.environment['HOME'] ?? '',
      'Android/Sdk/platform-tools/adb',
    ),
    '/usr/local/bin/adb',
    '/opt/homebrew/bin/adb',
  ];

  String? _resolved;

  Future<String?> _adb() async {
    if (_resolved != null) return _resolved;
    for (final candidate in _candidatePaths) {
      if (candidate.isEmpty) continue;
      final result = await runTool(candidate, [
        'version',
      ], timeout: const Duration(seconds: 8));
      if (result?.exitCode == 0) return _resolved = candidate;
    }
    return null;
  }

  @override
  Future<bool> isAvailable() async => await _adb() != null;

  @override
  Future<List<UsbDevice>> devices() async {
    final adb = await _adb();
    if (adb == null) return const [];

    final result = await runTool(adb, ['devices', '-l']);
    if (result == null || result.exitCode != 0) return const [];

    final devices = <UsbDevice>[];
    for (final line in const LineSplitter().convert(result.stdout.toString())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('List of devices')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      // `unauthorized` and `offline` are devices we cannot read yet; showing
      // them as browsable would just produce empty folders.
      if (parts[1] != 'device') continue;

      devices.add(
        UsbDevice(
          id: parts[0],
          label: _labelFrom(parts) ?? parts[0],
          rootPath: '/sdcard',
        ),
      );
    }
    return devices;
  }

  /// `adb devices -l` tags each line with `model:SM_G991B` and friends.
  String? _labelFrom(List<String> parts) {
    for (final part in parts) {
      if (part.startsWith('model:')) {
        return part.substring('model:'.length).replaceAll('_', ' ');
      }
    }
    return null;
  }

  @override
  Future<List<UsbEntry>> list(UsbDevice device, String path) async {
    final adb = await _adb();
    if (adb == null) return const [];

    // The trailing slash is load-bearing: `/sdcard` is a symlink to
    // `/storage/self/primary`, and `ls -la /sdcard` describes the link in one
    // line instead of listing what is inside it.
    final target = path.endsWith('/') ? path : '$path/';

    final result = await runTool(adb, [
      '-s',
      device.id,
      'shell',
      'ls',
      '-la',
      _quote(target),
    ]);
    if (result == null) return const [];

    // A phone that has been unplugged, locked, or had its authorisation
    // revoked answers on stderr and lists nothing — which reads exactly like
    // an empty folder unless it is called out. `ls` failing on one path (a
    // permission-denied folder, say) is not that, so only device-level
    // complaints count.
    final stderr = result.stderr.toString();
    if (describesNoDevice(stderr)) {
      throw UsbDeviceGone(
        'The phone stopped answering: ${stderr.trim().split('\n').first}. '
        'Check the cable and unlock the screen.',
      );
    }

    final entries = <UsbEntry>[];
    for (final line in const LineSplitter().convert(result.stdout.toString())) {
      final entry = _parseLsLine(line, path);
      if (entry != null) entries.add(entry);
    }

    entries.sort((a, b) {
      // Folders first, then alphabetical — the order every file browser uses.
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// `-rw-rw---- 1 root everybody 4096 2026-01-01 10:00 holiday photo.jpg`
  ///
  /// The name is taken as everything after the timestamp rather than as the
  /// last whitespace-separated field, so names containing spaces survive.
  static final RegExp _lsLine = RegExp(
    r'^([bcdlsp-])[rwxsStT-]{9}[.+]?\s+\S+\s+\S+\s+\S+\s+(\d+)\s+'
    r'\S+\s+\S+\s+(.+)$',
  );

  @visibleForTesting
  static UsbEntry? parseLsLine(String line, String parent) =>
      _parseLsLine(line, parent);

  static UsbEntry? _parseLsLine(String line, String parent) {
    final match = _lsLine.firstMatch(line.trimRight());
    if (match == null) return null;

    var name = match.group(3)!;
    // Symlinks render as `link -> target`; the link is what you can open.
    final arrow = name.indexOf(' -> ');
    if (arrow != -1) name = name.substring(0, arrow);
    if (name == '.' || name == '..' || name.isEmpty) return null;

    return UsbEntry(
      name: name,
      path: p.posix.join(parent, name),
      isDirectory: match.group(1) == 'd' || match.group(1) == 'l',
      size: int.tryParse(match.group(2)!) ?? 0,
    );
  }

  @override
  Future<String?> pull(
    UsbDevice device,
    UsbEntry entry,
    Directory destination, {
    ProgressCallback? onProgress,
  }) async {
    final adb = await _adb();
    if (adb == null) return null;

    await destination.create(recursive: true);
    final target = p.join(destination.path, entry.name);
    final poll = pollFileProgress(File(target), entry.size, onProgress);

    try {
      final result = await runTool(
        adb,
        ['-s', device.id, 'pull', entry.path, target],
        // Big videos over USB 2 are slow; a ceiling, not an expectation.
        timeout: const Duration(minutes: 30),
      );
      if (result == null || result.exitCode != 0) {
        debugPrint('adb pull failed: ${result?.stderr}');
        return null;
      }
      // One final reading, so the bar lands on 100% rather than wherever the
      // last poll happened to catch it.
      onProgress?.call(entry.size, entry.size);
      return target;
    } finally {
      poll.cancel();
    }
  }

  @override
  Future<bool> push(UsbDevice device, File file, String remoteDirectory) async {
    final adb = await _adb();
    if (adb == null) return false;

    final result = await runTool(adb, [
      '-s',
      device.id,
      'push',
      file.path,
      p.posix.join(remoteDirectory, p.basename(file.path)),
    ], timeout: const Duration(minutes: 30));
    if (result == null || result.exitCode != 0) {
      debugPrint('adb push failed: ${result?.stderr}');
      return false;
    }
    return true;
  }

  /// Paths reach the phone through a shell, so a space would split the
  /// argument in two before `ls` ever saw it.
  static String _quote(String path) => "'${path.replaceAll("'", r"'\''")}'";
}
