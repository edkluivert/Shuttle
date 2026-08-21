import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/usb/data/data_sources/adb_data_source.dart';

/// Lines below are copied verbatim from a real device (`adb shell ls -la
/// /sdcard/` on a Xiaomi 2201117SL), not invented — the shape of this output
/// varies between toybox versions and is the whole risk in this parser.
void main() {
  group('parsing an ls -la line', () {
    test('reads a plain file', () {
      final entry = AdbBackend.parseLsLine(
        '-rw-rw----  1 root everybody   3488 2025-08-10 18:45 photo.jpg',
        '/sdcard',
      );

      expect(entry, isNotNull);
      expect(entry!.name, 'photo.jpg');
      expect(entry.path, '/sdcard/photo.jpg');
      expect(entry.size, 3488);
      expect(entry.isDirectory, isFalse);
    });

    test('reads a directory', () {
      final entry = AdbBackend.parseLsLine(
        'drwxrwx---  2 root everybody   3488 2025-08-10 18:45 DCIM',
        '/sdcard',
      );

      expect(entry!.isDirectory, isTrue);
      expect(entry.name, 'DCIM');
    });

    test('keeps spaces in a filename', () {
      // Taking the last whitespace-separated field would have truncated this
      // to "photo.jpg" and produced a path that does not exist.
      final entry = AdbBackend.parseLsLine(
        '-rw-rw----  1 root everybody   120 2026-01-02 09:10 my holiday photo.jpg',
        '/sdcard/DCIM',
      );

      expect(entry!.name, 'my holiday photo.jpg');
      expect(entry.path, '/sdcard/DCIM/my holiday photo.jpg');
    });

    test('a symlink is browsable, like the folder it points at', () {
      // /sdcard itself is one of these, so treating links as plain files
      // would make the top of the tree unopenable.
      final entry = AdbBackend.parseLsLine(
        'lrw-r--r--  1 root root 21 2009-01-01 01:00 sdcard -> /storage/self/primary',
        '/',
      );

      expect(entry!.name, 'sdcard');
      expect(entry.isDirectory, isTrue);
    });

    test('ignores the total line and the dot entries', () {
      expect(AdbBackend.parseLsLine('total 164', '/sdcard'), isNull);
      expect(
        AdbBackend.parseLsLine(
          'drwxrwx---  2 root everybody 3488 2025-08-10 18:45 .',
          '/sdcard',
        ),
        isNull,
      );
      expect(
        AdbBackend.parseLsLine(
          'drwxrwx---  2 root everybody 3488 2025-08-10 18:45 ..',
          '/sdcard',
        ),
        isNull,
      );
    });

    test('ignores anything that is not a listing', () {
      expect(AdbBackend.parseLsLine('', '/sdcard'), isNull);
      expect(
        AdbBackend.parseLsLine('ls: /nope: No such file', '/sdcard'),
        isNull,
      );
    });

    test('reads an SELinux-tagged line', () {
      // Some builds append a `.` or `+` to the permission block.
      final entry = AdbBackend.parseLsLine(
        '-rw-rw----. 1 root everybody 42 2026-01-02 09:10 tagged.txt',
        '/sdcard',
      );

      expect(entry?.name, 'tagged.txt');
      expect(entry?.size, 42);
    });
  });

  /// A phone that leaves mid-browse must not read as an empty folder.
  group('telling a vanished phone from an empty folder', () {
    test('device-level complaints are recognised', () {
      for (final stderr in [
        'error: device offline',
        'error: device not found',
        'error: no devices/emulators found',
        'error: device unauthorized.',
        'adb: error: closed',
      ]) {
        expect(AdbBackend.describesNoDevice(stderr), isTrue, reason: stderr);
      }
    });

    test('a per-path failure is not one', () {
      // The folder is unreadable; the phone is fine. Reporting this as a lost
      // device would send the user hunting for a cable problem.
      expect(
        AdbBackend.describesNoDevice('ls: /sdcard/Android/data: Permission denied'),
        isFalse,
      );
      expect(AdbBackend.describesNoDevice(''), isFalse);
    });
  });
}
