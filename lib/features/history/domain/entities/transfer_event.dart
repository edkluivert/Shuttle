import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:shuttle/core/utils/formatters.dart';

/// How a file travelled.
enum TransferWay { browser, network, usb }

extension TransferWayLabel on TransferWay {
  String get label => switch (this) {
    TransferWay.browser => 'Browser',
    TransferWay.network => 'Wi-Fi',
    TransferWay.usb => 'USB',
  };
}

/// Something that moved: which file, which way, and who was at the other end.
class TransferEvent extends Equatable {
  const TransferEvent({
    required this.name,
    required this.bytes,
    required this.peer,
    required this.incoming,
    required this.at,
    this.way = TransferWay.browser,
    this.path,
  });

  final String name;
  final int bytes;

  /// The other end. A browser has no name to give, so this is its address —
  /// on a home network, enough to tell the phone from the laptop.
  final String peer;

  /// True when the file came *to* this device.
  final bool incoming;

  final TransferWay way;
  final DateTime at;

  /// Where the file is on *this* device — the copy that arrived, or the
  /// original that was sent.
  ///
  /// Without it a log entry is only a name, and a list of names is not
  /// something you can open. Null for entries written before this was
  /// recorded, and for the one case where there is no local file: a browser
  /// uploading through the web page names the file, but nothing on this side
  /// ever held it.
  final String? path;

  /// Whether the file is still where it was left.
  ///
  /// Checked against the disk rather than trusted: files get moved, renamed
  /// and deleted between a transfer and someone tapping the row, and offering
  /// to open something that is gone is worse than not offering.
  bool get existsLocally {
    final at = path;
    return at != null && File(at).existsSync();
  }

  String get sizeLabel => formatBytes(bytes);

  /// "just now", "4 min ago" — a clock time would make the reader do the
  /// subtraction themselves.
  String get whenLabel {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inSeconds < 45) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
    if (elapsed.inDays == 1) return 'yesterday';
    return '${elapsed.inDays} d ago';
  }

  /// The day this belongs to, for grouping a long history.
  DateTime get day => DateTime(at.year, at.month, at.day);

  @override
  List<Object?> get props => [name, bytes, peer, incoming, way, at, path];
}
