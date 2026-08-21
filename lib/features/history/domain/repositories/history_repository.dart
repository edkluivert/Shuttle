import 'package:shuttle/features/history/domain/entities/transfer_event.dart';

/// The log of everything this device has sent or received.
///
/// A stream rather than a getter: three features write to it — the browser
/// server, Wi-Fi pulls and USB copies — and the screen showing it has no way
/// to know when any of them will.
abstract interface class HistoryRepository {
  Stream<List<TransferEvent>> watch();

  List<TransferEvent> get current;

  Future<void> record(TransferEvent event);

  Future<void> clear();
}
