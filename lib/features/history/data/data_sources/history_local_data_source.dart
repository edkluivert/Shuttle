import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shuttle/features/history/data/models/transfer_event_model.dart';
import 'package:shuttle/features/history/domain/entities/transfer_event.dart';

/// The log on disk.
abstract interface class HistoryLocalDataSource {
  List<TransferEvent> read();

  Future<void> write(List<TransferEvent> events);
}

class HistoryLocalDataSourceImpl implements HistoryLocalDataSource {
  HistoryLocalDataSourceImpl(this.file);

  final File file;

  @override
  List<TransferEvent> read() {
    try {
      if (!file.existsSync()) return const [];
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TransferEventModel.fromJson)
          .toList(growable: false);
    } catch (e) {
      // A corrupt log is not worth failing to launch over, and there is
      // nothing in it that cannot be lost.
      debugPrint('Could not read history: $e');
      return const [];
    }
  }

  @override
  Future<void> write(List<TransferEvent> events) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(
          events.map(TransferEventModel.toJson).toList(growable: false),
        ),
      );
    } catch (e) {
      debugPrint('Could not save history: $e');
    }
  }
}
