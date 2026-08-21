import 'dart:async';
import 'dart:io';

import 'package:shuttle/features/usb/domain/entities/usb_entities.dart';

export 'package:shuttle/features/usb/domain/entities/usb_entities.dart';

typedef ProgressCallback = void Function(int received, int total);

/// A way of talking to a phone over USB.
///
/// There is deliberately more than one. USB is not a network: the cable
/// carries a device protocol, and which protocol is available depends on what
/// the phone exposes and what the computer has installed. Rather than pick
/// one and fail on everyone else's setup, the app asks each backend whether
/// it can work here and uses the first that can.
///
/// None of this runs on the phone itself — a phone is never the USB host.
/// These are for the desktop side of the cable.
abstract class UsbBackend {
  /// What to call this in the UI.
  String get name;

  /// Shown when [isAvailable] is false: how to make this backend work.
  String get setupHint;

  /// Whether the helper this backend drives is installed and runnable.
  Future<bool> isAvailable();

  /// Whether asking this backend for a device is cheap.
  ///
  /// The automatic scan only tries backends that answer quickly: MTP cannot
  /// say whether a phone is there without walking it, which is minutes, and
  /// nobody wants that to start on its own.
  bool get scansQuickly;

  Future<List<UsbDevice>> devices();

  /// A better name for the device than [devices] could give, learned while
  /// listing it. Null when there is nothing to improve on.
  String? get discoveredLabel;

  Future<List<UsbEntry>> list(UsbDevice device, String path);

  /// Copies a file off the phone into [destination]. Returns the local path.
  Future<String?> pull(
    UsbDevice device,
    UsbEntry entry,
    Directory destination, {
    ProgressCallback? onProgress,
  });

  /// Copies a local file onto the phone under [remoteDirectory].
  Future<bool> push(UsbDevice device, File file, String remoteDirectory);
}

/// The phone stopped answering partway through — unplugged, locked, or (the
/// common one on Android) its USB mode fell back to charging-only.
///
/// This exists because the alternative is worse: a listing that comes back
/// empty is indistinguishable from an empty folder, so the browser used to
/// say "Nothing here" about a phone that was no longer on the other end of
/// the cable. Backends throw this instead of returning `[]`, and the UI says
/// what actually happened.
class UsbDeviceGone implements Exception {
  const UsbDeviceGone(this.message);

  final String message;

  @override
  String toString() => 'UsbDeviceGone: $message';
}

/// Reports a copy's progress by watching the destination file grow.
///
/// Both helpers print progress, in two different formats, to two different
/// streams — and `adb`'s is a bare percentage with no byte counts at all.
/// Watching the file is uniform across backends, needs no output parsing, and
/// gives real byte figures, which is what the UI actually wants to show.
///
/// The caller must cancel the returned timer when the copy finishes.
Timer pollFileProgress(File target, int total, ProgressCallback? onProgress) {
  return Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (onProgress == null) return;
    try {
      // Not yet created is simply zero bytes so far, not an error.
      final received = target.existsSync() ? target.lengthSync() : 0;
      onProgress(received, total);
    } catch (_) {
      // The file can be renamed out from under us as the copy completes.
    }
  });
}

/// Runs a helper binary, returning null rather than throwing when it is
/// missing — "not installed" is a normal answer here, not an error.
Future<ProcessResult?> runTool(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    return await Process.run(executable, arguments).timeout(timeout);
  } catch (_) {
    return null;
  }
}
