import 'package:equatable/equatable.dart';
import 'package:shuttle/core/utils/formatters.dart';

/// A transfer in flight, as the UI needs to describe it.
///
/// Carries the batch position as well as the byte counts: copying seven files
/// and being told only about the current one reads as a progress bar that
/// keeps restarting.
class TransferProgress extends Equatable {
  const TransferProgress({
    required this.name,
    required this.received,
    required this.total,
    this.fileIndex = 1,
    this.fileCount = 1,
    this.bytesPerSecond,
  });

  final String name;
  final int received;

  /// -1 when the size is not known up front, which is normal for a stream
  /// whose sender did not send a length.
  final int total;

  final int fileIndex;
  final int fileCount;
  final double? bytesPerSecond;

  bool get isBatch => fileCount > 1;

  /// Null while the total is unknown — the UI shows an indeterminate bar
  /// rather than inventing a percentage.
  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  String get receivedLabel => formatBytes(received);
  String get totalLabel => total > 0 ? formatBytes(total) : '';

  /// "12 MB of 48 MB" — or just the moving figure when there is no total.
  String get bytesLabel =>
      total > 0 ? '$receivedLabel of $totalLabel' : receivedLabel;

  String? get speedLabel {
    final speed = bytesPerSecond;
    if (speed == null || speed <= 0) return null;
    return '${formatBytes(speed.round())}/s';
  }

  String? get remainingLabel {
    final speed = bytesPerSecond;
    if (speed == null || speed <= 0 || total <= 0) return null;
    final remaining = total - received;
    if (remaining <= 0) return null;

    final seconds = (remaining / speed).round();
    if (seconds < 5) return 'almost done';
    if (seconds < 60) return '$seconds s left';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min left';
    return '${(minutes / 60).toStringAsFixed(1)} h left';
  }

  TransferProgress copyWith({
    int? received,
    int? total,
    double? bytesPerSecond,
  }) => TransferProgress(
    name: name,
    received: received ?? this.received,
    total: total ?? this.total,
    fileIndex: fileIndex,
    fileCount: fileCount,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
  );

  @override
  List<Object?> get props => [
    name,
    received,
    total,
    fileIndex,
    fileCount,
    bytesPerSecond,
  ];
}

/// Turns a series of byte counts into a smoothed rate.
///
/// A raw delta between two samples swings wildly — USB and Wi-Fi both deliver
/// in bursts — and a number flickering between 2 MB/s and 40 MB/s is worse
/// than none.
class TransferRate {
  TransferRate({this.smoothing = 0.3});

  final double smoothing;

  DateTime? _lastAt;
  int _lastBytes = 0;
  double? _rate;

  double? get bytesPerSecond => _rate;

  void update(int received, DateTime now) {
    final lastAt = _lastAt;
    if (lastAt == null) {
      _lastAt = now;
      _lastBytes = received;
      return;
    }

    final elapsed = now.difference(lastAt).inMicroseconds / 1000000;
    // Too soon to measure: dividing by a few milliseconds produces nonsense.
    if (elapsed < 0.25) return;

    final delta = received - _lastBytes;
    _lastAt = now;
    _lastBytes = received;
    if (delta < 0) return; // A new file in the batch; wait for the next tick.

    final sample = delta / elapsed;
    _rate = _rate == null
        ? sample
        : (_rate! * (1 - smoothing)) + (sample * smoothing);
  }

  void reset() {
    _lastAt = null;
    _lastBytes = 0;
    _rate = null;
  }
}
