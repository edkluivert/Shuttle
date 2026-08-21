import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/features/transfer/domain/entities/transfer_progress.dart';

void main() {
  group('what the progress bar says', () {
    test('shows both figures moving', () {
      const progress = TransferProgress(
        name: 'clip.mov',
        received: 12 * 1024 * 1024,
        total: 48 * 1024 * 1024,
      );

      // No decimal above ten — 12 MB, not 12.0 MB. Precision nobody needs
      // just makes a moving number harder to read.
      expect(progress.bytesLabel, '12 MB of 48 MB');
      expect(progress.fraction, closeTo(0.25, 0.001));
    });

    test('an unknown total means no percentage, not a fake one', () {
      const progress =
          TransferProgress(name: 'stream.bin', received: 2048, total: -1);

      expect(progress.fraction, isNull);
      // Still worth showing what has arrived, just without a denominator.
      expect(progress.bytesLabel, '2.0 KB');
    });

    test('never runs past 100%, even if the server undercounted', () {
      const progress =
          TransferProgress(name: 'a', received: 1200, total: 1000);
      expect(progress.fraction, 1.0);
    });

    test('the batch position is only shown for a batch', () {
      const single = TransferProgress(name: 'a', received: 0, total: 1);
      const batch = TransferProgress(
        name: 'a',
        received: 0,
        total: 1,
        fileIndex: 3,
        fileCount: 7,
      );

      expect(single.isBatch, isFalse);
      expect(batch.isBatch, isTrue);
    });

    test('speed reads as a rate', () {
      const progress = TransferProgress(
        name: 'a',
        received: 0,
        total: 1,
        bytesPerSecond: 5 * 1024 * 1024,
      );
      expect(progress.speedLabel, '5.0 MB/s');
    });

    test('no speed yet means no speed shown', () {
      const progress = TransferProgress(name: 'a', received: 0, total: 1);
      expect(progress.speedLabel, isNull);
      expect(progress.remainingLabel, isNull);
    });

    test('time left is phrased at the scale it matters', () {
      TransferProgress at(int received, int total, double rate) =>
          TransferProgress(
            name: 'a',
            received: received,
            total: total,
            bytesPerSecond: rate,
          );

      expect(at(0, 1000, 1000).remainingLabel, 'almost done');
      expect(at(0, 30000, 1000).remainingLabel, '30 s left');
      expect(at(0, 600000, 1000).remainingLabel, '10 min left');
      expect(at(0, 7200000, 1000).remainingLabel, '2.0 h left');
    });

    test('a finished transfer stops predicting', () {
      const done = TransferProgress(
        name: 'a',
        received: 1000,
        total: 1000,
        bytesPerSecond: 1000,
      );
      expect(done.remainingLabel, isNull);
    });
  });

  group('smoothing the rate', () {
    final start = DateTime(2026, 1, 1, 12);

    test('the first sample cannot produce a rate', () {
      final rate = TransferRate()..update(0, start);
      expect(rate.bytesPerSecond, isNull);
    });

    test('samples closer than a quarter second are ignored', () {
      // Dividing a byte count by a few milliseconds produces nonsense like
      // "800 MB/s" on a USB 2 cable.
      final rate = TransferRate()
        ..update(0, start)
        ..update(1000, start.add(const Duration(milliseconds: 50)));

      expect(rate.bytesPerSecond, isNull);
    });

    test('a steady stream settles on its true rate', () {
      final rate = TransferRate();
      var at = start;
      var bytes = 0;

      // 1 MB/s for ten seconds.
      for (var i = 0; i < 10; i++) {
        rate.update(bytes, at);
        bytes += 1024 * 1024;
        at = at.add(const Duration(seconds: 1));
      }

      expect(rate.bytesPerSecond, closeTo(1024 * 1024, 1024 * 400));
    });

    test('a burst does not swing the reading wildly', () {
      final rate = TransferRate();
      var at = start;

      // Steady 1 MB/s, then one 10 MB second.
      rate.update(0, at);
      at = at.add(const Duration(seconds: 1));
      rate.update(1024 * 1024, at);
      final steady = rate.bytesPerSecond!;

      at = at.add(const Duration(seconds: 1));
      rate.update(11 * 1024 * 1024, at);

      // Smoothed, so it moves toward the burst without jumping to it.
      expect(rate.bytesPerSecond, greaterThan(steady));
      expect(rate.bytesPerSecond, lessThan(10 * 1024 * 1024));
    });

    test('the counter going backwards is a new file, not negative speed', () {
      final rate = TransferRate();
      var at = start;

      rate.update(0, at);
      at = at.add(const Duration(seconds: 1));
      rate.update(1024 * 1024, at);
      final before = rate.bytesPerSecond;

      // Next file in the batch starts from zero again.
      at = at.add(const Duration(seconds: 1));
      rate.update(0, at);

      expect(rate.bytesPerSecond, before,
          reason: 'the reading should hold, not go negative');
    });

    test('reset clears it for the next file', () {
      final rate = TransferRate()
        ..update(0, start)
        ..update(1024, start.add(const Duration(seconds: 1)));
      expect(rate.bytesPerSecond, isNotNull);

      rate.reset();
      expect(rate.bytesPerSecond, isNull);
    });
  });
}
