import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/usb/data/data_sources/usb_backend.dart';
import 'package:path/path.dart' as p;

/// Talks to a phone over MTP, through libmtp's command line tools.
///
/// This is the backend for phones that only expose MTP — Android with USB
/// debugging off, and anything where the user just picked "File transfer" on
/// the phone's USB prompt.
///
/// It shells out rather than speaking MTP directly, and that is not a
/// shortcut taken lightly: MTP is a USB protocol, macOS ships no MTP support
/// at all, and Dart has no USB stack, so the alternative is FFI bindings to
/// libmtp and libusb plus USB device entitlements.
///
/// ## Why this indexes the whole device up front
///
/// libmtp's CLI has no "list one folder" command — every tool walks the
/// entire device before printing anything. Measured on a Redmi Note 11S:
/// `mtp-folders` 1m45s, `mtp-files` 2m59s for 78,460 files. Listing a folder
/// on demand would therefore cost minutes *per tap*.
///
/// So the tree is read once, in full, and kept. The first open is slow and
/// says so; everything after it is instant. `mtp-filetree` is the one command
/// that returns names, ids and structure together — the others each return
/// only half of it, and two slow walks are worse than one.
class MtpBackend implements UsbBackend {
  @override
  String get name => 'MTP';

  @override
  String get setupHint =>
      'Install libmtp (`brew install libmtp`), then unlock the phone and set '
      'its USB mode to "File transfer".';

  /// Homebrew's bin directory is not on the PATH of an app launched from
  /// Finder — a GUI bundle does not inherit a login shell's environment.
  static const List<String> _searchPaths = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
  ];

  final Map<String, String?> _tools = {};

  /// id → entry, and id → children, built once per connection.
  Map<String, List<UsbEntry>>? _childrenByParent;

  static const String rootId = '';

  Future<String?> _tool(String name) async {
    if (_tools.containsKey(name)) return _tools[name];

    for (final dir in _searchPaths) {
      final candidate = p.join(dir, name);
      if (File(candidate).existsSync()) return _tools[name] = candidate;
    }
    // Last resort: whatever PATH offers.
    final probe = await runTool(name, [], timeout: const Duration(seconds: 5));
    return _tools[name] = probe == null ? null : name;
  }

  @override
  Future<bool> isAvailable() async => await _tool('mtp-filetree') != null;

  /// Never automatically: the only way to know what is on an MTP device is to
  /// walk all of it.
  @override
  bool get scansQuickly => false;

  String? _label;

  @override
  String? get discoveredLabel => _label;

  /// Provisional, and deliberately without asking the phone anything.
  ///
  /// `mtp-detect` used to run here purely to answer "is a phone there?" — but
  /// every libmtp tool opens its own USB session, and each session is another
  /// chance for the phone to drop out of File-transfer mode before the walk
  /// that follows begins. That is not hypothetical: a Redmi Note 11S answered
  /// `mtp-detect`, then re-enumerated as charging-only (`2717:ff48` →
  /// `2717:ff08`) before `mtp-filetree` could run, which is what "Nothing
  /// here" used to mean.
  ///
  /// The walk answers both questions on its own — it names the device in its
  /// banner, and returns in milliseconds when nothing is connected — so the
  /// session is spent there instead. [list] throws [UsbDeviceGone] when there
  /// turns out to be no phone, and the real name replaces this one.
  @override
  Future<List<UsbDevice>> devices() async {
    if (await _tool('mtp-filetree') == null) return const [];
    // libmtp addresses one device at a time; there is no id to pass around.
    return [
      UsbDevice(id: 'mtp', label: _label ?? 'Phone (MTP)', rootPath: rootId),
    ];
  }

  /// The phone's name out of the walk's own banner:
  ///
  ///     Device 0 (VID=2717 and PID=ff48) is a Xiaomi Mi-2s (MTP).
  ///
  /// Null when the output has no such line — a device that is there but
  /// unnamed is still a device, so callers keep their provisional label
  /// rather than treating this as absence. Absence is [describesNoDevice].
  ///
  /// Matched one line at a time: `\s+` and `.+?` both cross newlines happily,
  /// and a multiline pattern here runs from the banner into the tree.
  @visibleForTesting
  static String? parseTreeLabel(String output) {
    final pattern = RegExp(r'^Device\s+\d+\s+\(.*?\)\s+is\s+(?:an?\s+)?(.+?)\.?\s*$');
    for (final line in const LineSplitter().convert(output)) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        final label = match.group(1)!.trim();
        if (label.isNotEmpty) return label;
      }
    }
    return null;
  }

  @override
  Future<List<UsbEntry>> list(UsbDevice device, String path) async {
    // Only a tree with something in it is worth keeping. Caching an empty one
    // would make a single failed walk permanent: every folder for the rest of
    // the session would answer "empty" without touching the phone again.
    final tree = _childrenByParent ?? await _readTree();
    if (tree.isNotEmpty) _childrenByParent = tree;
    return tree[path] ?? const [];
  }

  /// Throws away the cached tree so the next listing re-reads the device.
  void invalidate() => _childrenByParent = null;

  Future<Map<String, List<UsbEntry>>> _readTree() async {
    final fileTree = await _tool('mtp-filetree');
    if (fileTree == null) return {};

    final treeResult = await runTool(
      fileTree,
      [],
      // The full walk is minutes on a phone with tens of thousands of files.
      timeout: const Duration(minutes: 15),
    );
    if (treeResult == null) {
      throw const UsbDeviceGone(
        'Reading the phone took too long and was given up on. Unplug it, '
        'plug it back in, and try again.',
      );
    }

    final treeOutput = treeResult.stdout.toString();
    // Every libmtp tool opens its own session, so the phone can be there for
    // `mtp-detect` and gone by the time the walk starts — and it exits 0
    // while saying so, which is why the text is what gets checked.
    if (describesNoDevice(treeOutput)) throw UsbDeviceGone(deviceGoneMessage);

    // The walk names the phone, so nothing else has to ask it.
    _label = parseTreeLabel(treeOutput) ?? _label;

    // `mtp-filetree` gives names and structure but marks nothing as a folder,
    // and carries no sizes. `mtp-files` lists *only* files, with sizes — so
    // it settles both questions. Without it an empty folder is indis-
    // tinguishable from a file, and tapping one fails with no explanation.
    final files = await _tool('mtp-files');
    final filesResult = files == null
        ? null
        : await runTool(files, [], timeout: const Duration(minutes: 15));
    final sizeOutput = filesResult?.stdout.toString();

    return parseFileTree(
      treeOutput,
      // A second walk means a second session, and the phone can drop out
      // between them too. Sizes are a nicety; the tree is the screen — so a
      // vanished device here degrades to "no sizes" rather than losing the
      // listing that was already read successfully.
      fileSizes: sizeOutput == null || describesNoDevice(sizeOutput)
          ? null
          : parseFileSizes(sizeOutput),
    );
  }

  /// libmtp's way of saying nothing is on the cable. It prints this to
  /// *stdout* and still exits 0, so neither the exit code nor stderr can be
  /// used to tell this apart from a real listing.
  @visibleForTesting
  static bool describesNoDevice(String output) =>
      output.contains('No raw devices found') ||
      output.contains('Found 0 device') ||
      output.contains('Unable to open raw device');

  /// Written for the case that actually happens: Android phones — Xiaomi and
  /// friends especially — drop back to charging-only when the screen locks or
  /// after a long transfer, and the USB device re-enumerates under a
  /// different product id. Nothing on the desktop side can fix that.
  static const String deviceGoneMessage =
      'The phone stopped answering over MTP. Unlock it and set USB mode back '
      'to "File transfer" — Android drops to charging-only when it locks. '
      '(Developer options → Default USB configuration → File Transfer makes '
      'it stick.)';

  /// File id → size, from `mtp-files`.
  ///
  /// Note the format: `File size 665919 (0x…) bytes` has **no colon** after
  /// "File size", unlike every neighbouring field. Reading it as `File size:`
  /// reported every file on the device as 0 bytes.
  @visibleForTesting
  static Map<String, int> parseFileSizes(String output) {
    final sizes = <String, int>{};
    String? id;

    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('File ID:')) {
        id = trimmed.substring('File ID:'.length).trim();
      } else if (id != null && trimmed.startsWith('File size')) {
        final digits = RegExp(r'(\d+)').firstMatch(trimmed)?.group(1);
        sizes[id] = int.tryParse(digits ?? '') ?? -1;
        id = null;
      }
    }
    return sizes;
  }

  /// `mtp-filetree` prints two spaces per level, then `<id> <name>`:
  ///
  ///     7 Pictures
  ///       90 IMG_20181201_181924_6.jpg
  ///     1 Android
  ///       2609 data
  ///
  /// Nothing in this output marks a folder. When [fileSizes] is supplied
  /// (from `mtp-files`, which lists only files) it is the authority: anything
  /// absent from it is a folder, empty ones included. Without it the parser
  /// falls back to "has children", which cannot see an empty folder.
  @visibleForTesting
  static Map<String, List<UsbEntry>> parseFileTree(
    String output, {
    Map<String, int>? fileSizes,
  }) {
    final children = <String, List<UsbEntry>>{};
    // Depth → the id of the entry opened at that depth, so a line's parent is
    // whatever sits one level shallower.
    final openAtDepth = <int, String>{};
    final hasChildren = <String>{};

    for (final line in const LineSplitter().convert(output)) {
      if (line.trim().isEmpty) continue;

      final match = RegExp(r'^( *)(\d+)\s+(.*)$').firstMatch(line);
      if (match == null) continue; // Banner lines, "Storage:", etc.

      final depth = match.group(1)!.length ~/ 2;
      final id = match.group(2)!;
      final name = match.group(3)!.trim();
      if (name.isEmpty) continue;

      final parent = depth == 0 ? rootId : (openAtDepth[depth - 1] ?? rootId);
      openAtDepth[depth] = id;
      // Anything deeper is stale the moment we move back up a level.
      openAtDepth.removeWhere((key, _) => key > depth);

      if (parent != rootId) hasChildren.add(parent);

      children
          .putIfAbsent(parent, () => [])
          .add(
            UsbEntry(
              name: name,
              path: id,
              isDirectory: false, // Fixed up below, once children are known.
              size: -1, // MTP's tree carries no sizes.
            ),
          );
    }

    // Second pass: settle what is a folder, now that the whole tree is known.
    for (final entry in children.entries) {
      entry.value.setAll(
        0,
        entry.value.map((e) {
          final isDirectory = fileSizes != null
              ? !fileSizes.containsKey(e.path)
              : hasChildren.contains(e.path) || children.containsKey(e.path);

          return UsbEntry(
            name: e.name,
            path: e.path,
            isDirectory: isDirectory,
            size: isDirectory ? -1 : (fileSizes?[e.path] ?? -1),
          );
        }),
      );
      entry.value.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    return children;
  }

  @override
  Future<String?> pull(
    UsbDevice device,
    UsbEntry entry,
    Directory destination, {
    ProgressCallback? onProgress,
  }) async {
    final getFile = await _tool('mtp-getfile');
    if (getFile == null) return null;

    await destination.create(recursive: true);
    final target = p.join(destination.path, entry.name);
    final poll = pollFileProgress(File(target), entry.size, onProgress);

    try {
      // `mtp-getfile <fileid> <local filename>` — the id is what the tree
      // stores as the path, since MTP addresses files by id, not by path.
      final result = await runTool(getFile, [
        entry.path,
        target,
      ], timeout: const Duration(minutes: 30));
      if (result == null || result.exitCode != 0) {
        debugPrint('mtp-getfile failed: ${result?.stderr}');
        return null;
      }
      if (!File(target).existsSync()) return null;

      onProgress?.call(entry.size, entry.size);
      return target;
    } finally {
      poll.cancel();
    }
  }

  @override
  Future<bool> push(UsbDevice device, File file, String remoteDirectory) async {
    final sendFile = await _tool('mtp-sendfile');
    if (sendFile == null) return false;

    // `sendfile <local filename> <remote filename>` — there is no folder
    // argument, so the file lands wherever libmtp's default is. The tree
    // cache is dropped so the new file shows up on the next listing.
    final result = await runTool(sendFile, [
      file.path,
      p.basename(file.path),
    ], timeout: const Duration(minutes: 30));
    if (result == null || result.exitCode != 0) {
      debugPrint('mtp-sendfile failed: ${result?.stderr}');
      return false;
    }
    invalidate();
    return true;
  }
}
