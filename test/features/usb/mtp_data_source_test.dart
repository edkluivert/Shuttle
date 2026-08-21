import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/usb/data/data_sources/mtp_data_source.dart';

/// The sample is copied verbatim from `mtp-filetree` on a Redmi Note 11S —
/// including the banner lines the tool prints before the tree, which are the
/// thing most likely to be parsed as entries by mistake.
const String _realOutput = '''
Device 0 (VID=2717 and PID=ff48) is a Xiaomi Mi-2s (MTP).
Attempting to connect device(s)
Android device detected, assigning default bug flags
Device:
Storage: Internal shared storage
7 Pictures
  90 IMG_20181201_181924_6.jpg
  179 .trashed-1788349862-1785530061356.jpg
  70 IMG_20180818_122225.jpg
1 Android
  2609 data
    2707 com.google.android.apps.youtube.creator
      2818 cache
    2738 com.google.android.adservices.api
      2819 files
  2608 obb
23 Download
  4102 invoice.pdf
''';

void main() {
  group('parsing mtp-filetree', () {
    final tree = MtpBackend.parseFileTree(_realOutput);

    test('the banner lines are not mistaken for entries', () {
      final rootNames =
          tree[MtpBackend.rootId]!.map((e) => e.name).toList();

      expect(rootNames, isNot(contains('Storage: Internal shared storage')));
      expect(rootNames, isNot(contains('Attempting to connect device(s)')));
      // `Device 0 (VID=...)` begins with a word, not an id, so it cannot pass
      // the `<id> <name>` shape either.
      expect(rootNames, hasLength(3));
    });

    test('top level holds the real folders', () {
      final root = tree[MtpBackend.rootId]!;
      expect(root.map((e) => e.name), containsAll(<String>['Pictures', 'Android', 'Download']));
      expect(root.every((e) => e.isDirectory), isTrue);
    });

    test('children are keyed by their parent id', () {
      final pictures = tree['7']!;
      expect(pictures.map((e) => e.name), contains('IMG_20181201_181924_6.jpg'));
      expect(pictures, hasLength(3));
    });

    test('a file carries its MTP id as its path', () {
      // mtp-getfile addresses files by id, never by path, so the id is what
      // has to survive into the entry.
      final invoice = tree['23']!.firstWhere((e) => e.name == 'invoice.pdf');
      expect(invoice.path, '4102');
      expect(invoice.isDirectory, isFalse);
    });

    test('nesting several levels deep keeps the right parent', () {
      // 1 Android → 2609 data → 2707 com.google... → 2818 cache
      expect(tree['1']!.map((e) => e.name), containsAll(<String>['data', 'obb']));
      expect(tree['2609']!.map((e) => e.name),
          contains('com.google.android.apps.youtube.creator'));
      expect(tree['2707']!.map((e) => e.name), contains('cache'));
    });

    test('coming back up a level does not reparent onto a stale branch', () {
      // `2608 obb` sits at depth 1 again after a depth-3 line. Without
      // clearing the deeper levels it would be filed under `com.google…`.
      final android = tree['1']!.map((e) => e.name).toList();
      expect(android, contains('obb'));
      expect(tree['2707']!.map((e) => e.name), isNot(contains('obb')));
    });

    test('anything with children is a folder, leaves are files', () {
      final android = tree[MtpBackend.rootId]!
          .firstWhere((e) => e.name == 'Android');
      final photo =
          tree['7']!.firstWhere((e) => e.name == 'IMG_20180818_122225.jpg');

      expect(android.isDirectory, isTrue);
      expect(photo.isDirectory, isFalse);
    });

    test('folders sort before files', () {
      final root = tree[MtpBackend.rootId]!;
      final firstFileIndex = root.indexWhere((e) => !e.isDirectory);
      expect(firstFileIndex, -1, reason: 'this sample is all folders');

      final pictures = tree['7']!;
      expect(pictures.every((e) => !e.isDirectory), isTrue);
    });

    test('sizes are reported as unknown, not as zero', () {
      // MTP's tree carries no sizes; claiming 0 B would be a lie the UI then
      // renders confidently.
      expect(tree['7']!.every((e) => e.size < 0), isTrue);
    });

    test('empty output is empty, not a crash', () {
      expect(MtpBackend.parseFileTree(''), isEmpty);
      expect(MtpBackend.parseFileTree('no devices found'), isEmpty);
    });
  });

  group('mtp-files settles what the tree cannot', () {
    // Verbatim record shape from `mtp-files`. Note "File size" has no colon,
    // unlike every field around it — reading it as "File size:" reported
    // every file on the device as zero bytes.
    const filesOutput = '''
libmtp version: 1.1.23

Listing File Information on Device with name: (NULL)
File ID: 90
   Filename: IMG_20181201_181924_6.jpg
   File size 665919 (0x00000000000A293F) bytes
   Parent ID: 7
   Storage ID: 0x00010001
   Filetype: JPEG file
File ID: 4102
   Filename: invoice.pdf
   File size 20480 (0x0000000000005000) bytes
   Parent ID: 23
''';

    test('reads sizes despite the missing colon', () {
      final sizes = MtpBackend.parseFileSizes(filesOutput);
      expect(sizes['90'], 665919);
      expect(sizes['4102'], 20480);
    });

    test('an empty folder is a folder, not a file', () {
      // This is the bug that made a real pull fail: `.backups` had a child
      // folder with no children of its own, so "leaf means file" called it a
      // file and mtp-getfile refused it.
      const tree = '''
25 .backups
  45 emptyfolder
7 Pictures
  90 IMG_20181201_181924_6.jpg
''';

      final withoutFiles = MtpBackend.parseFileTree(tree);
      expect(
        withoutFiles['25']!.single.isDirectory,
        isFalse,
        reason: 'the fallback cannot see this — that is why sizes are read',
      );

      final withFiles = MtpBackend.parseFileTree(
        tree,
        fileSizes: MtpBackend.parseFileSizes(filesOutput),
      );
      expect(withFiles['25']!.single.name, 'emptyfolder');
      expect(withFiles['25']!.single.isDirectory, isTrue);
    });

    test('real files carry their size through', () {
      final tree = MtpBackend.parseFileTree(
        '7 Pictures\n  90 IMG_20181201_181924_6.jpg\n',
        fileSizes: MtpBackend.parseFileSizes(filesOutput),
      );

      final photo = tree['7']!.single;
      expect(photo.isDirectory, isFalse);
      expect(photo.size, 665919);
    });
  });

  /// `mtp-detect` is no longer run at all: it existed only to answer "is a
  /// phone there?", and every libmtp tool opens its own USB session — one
  /// more chance for the phone to leave File-transfer mode before the walk.
  /// The walk answers both questions itself, from its own banner.
  group('naming the phone from the walk itself', () {
    test('reads the name out of the banner', () {
      expect(
        MtpBackend.parseTreeLabel(_realOutput),
        'Xiaomi Mi-2s (MTP)',
      );
    });

    test('a banner without the article still parses', () {
      expect(
        MtpBackend.parseTreeLabel(
          'Device 0 (VID=04e8 and PID=6860) is Samsung Galaxy.',
        ),
        'Samsung Galaxy',
      );
    });

    test('output with no banner leaves the caller its own label', () {
      // Unnamed is not absent — that question is `describesNoDevice`.
      expect(MtpBackend.parseTreeLabel('7 Pictures\n  90 a.jpg\n'), isNull);
      expect(MtpBackend.parseTreeLabel(''), isNull);
    });

    test('the tree below the banner is not mistaken for it', () {
      // `\s+` and `.+?` cross newlines, so a multiline pattern here would run
      // from the banner into the listing.
      expect(
        MtpBackend.parseTreeLabel(_realOutput),
        isNot(contains('Pictures')),
      );
    });
  });

  /// Every libmtp tool opens its own session, so the phone can answer
  /// `mtp-detect` and be gone by the time the tree walk runs — observed on a
  /// Redmi Note 11S, which reverted to charging-only after a long walk and
  /// re-enumerated under a different product id (ff48 → ff08). The tools say
  /// so on *stdout* and still exit 0, so the text is the only signal.
  group('telling a vanished phone from an empty one', () {
    test('libmtp saying nothing is connected is not an empty tree', () {
      expect(
        MtpBackend.describesNoDevice('   No raw devices found.\n'),
        isTrue,
      );
      expect(MtpBackend.describesNoDevice('   Found 0 device(s):'), isTrue);
      expect(
        MtpBackend.describesNoDevice('Unable to open raw device 0'),
        isTrue,
      );
    });

    test('a real listing is not mistaken for a vanished phone', () {
      expect(MtpBackend.describesNoDevice(_realOutput), isFalse);
    });

    test('a phone with genuinely nothing on it still parses as a tree', () {
      // Storage present, no entries — this one really is empty, and must not
      // be reported as a device that dropped off.
      const output = '''
Device 0 (VID=2717 and PID=ff48) is a Xiaomi Mi-2s (MTP).
Attempting to connect device(s)
Storage: Internal shared storage
''';

      expect(MtpBackend.describesNoDevice(output), isFalse);
      expect(MtpBackend.parseFileTree(output), isEmpty);
    });
  });
}
