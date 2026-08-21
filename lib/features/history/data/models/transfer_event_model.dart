import 'package:shuttle/features/history/domain/entities/transfer_event.dart';

/// Wire format for [TransferEvent].
///
/// Kept apart from the entity so the JSON shape can change — a field added by
/// a later version, a key renamed — without the domain knowing there is such
/// a thing as JSON.
abstract final class TransferEventModel {
  /// Tolerant by design: a log written by a newer version, or half-corrupted,
  /// should still yield the entries it can rather than losing the file.
  static TransferEvent fromJson(Map<String, dynamic> json) => TransferEvent(
    name: json['name']?.toString() ?? 'file',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    peer: json['peer']?.toString() ?? 'unknown',
    incoming: json['incoming'] == true,
    way: TransferWay.values.firstWhere(
      (w) => w.name == json['way'],
      orElse: () => TransferWay.browser,
    ),
    at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
    // Absent from every entry written before the log recorded it. Those rows
    // still read correctly; they just cannot be opened.
    path: json['path']?.toString(),
  );

  static Map<String, dynamic> toJson(TransferEvent event) => {
    'name': event.name,
    'bytes': event.bytes,
    'peer': event.peer,
    'incoming': event.incoming,
    'way': event.way.name,
    'at': event.at.toIso8601String(),
    if (event.path != null) 'path': event.path,
  };
}
