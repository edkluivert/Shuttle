import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

/// Opens a file and, if it will not open, says why.
///
/// Handed straight to an `onTap`. A tap that silently does nothing is the
/// worst outcome here — the file may be gone, or the phone may have nothing
/// installed that reads it, and both are worth a sentence.
Future<void> openFromUi(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.of(context);
  final problem = await openInSystemViewer(path);
  if (problem == null) return;

  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(problem)));
}

/// Hands a file — or a folder — to whatever the operating system opens it
/// with. Returns null when it worked, or a sentence to show the user.
///
/// Two mechanisms, because no one package covers both worlds. The phones need
/// the plugin: Android will not let one app hand another a `file://` URI, so
/// the path has to be wrapped in a `content://` one through a FileProvider,
/// and doing that by hand means native code in the app. The desktops need no
/// dependency at all — each already ships a command that does exactly this,
/// and the app is shelling out to `adb` two features over anyway.
Future<String?> openInSystemViewer(String path) async {
  if (!File(path).existsSync() && !Directory(path).existsSync()) {
    return 'That file is no longer there.';
  }

  if (Platform.isAndroid || Platform.isIOS) {
    final result = await OpenFilex.open(path);
    return switch (result.type) {
      ResultType.done => null,
      // The common one, and worth its own wording: nothing is broken, the
      // phone simply has nothing installed that reads this kind of file.
      ResultType.noAppToOpen => 'No app on this device opens that kind of '
          'file.',
      ResultType.fileNotFound => 'That file is no longer there.',
      ResultType.permissionDenied => 'This app is not allowed to open that '
          'file.',
      ResultType.error => result.message,
    };
  }

  final (executable, arguments) = switch (Platform.operatingSystem) {
    'macos' => ('open', [path]),
    // Through the shell, not `explorer` directly: explorer exits non-zero even
    // when it succeeded, so its result cannot be read.
    'windows' => ('cmd', ['/c', 'start', '', path]),
    _ => ('xdg-open', [path]),
  };

  try {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      return error.isEmpty ? 'Could not open that file.' : error;
    }
    return null;
  } catch (e) {
    return 'Could not open that file: $e';
  }
}
