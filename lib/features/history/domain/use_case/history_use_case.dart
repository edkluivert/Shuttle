import 'package:shuttle/features/history/domain/entities/transfer_event.dart';
import 'package:shuttle/features/history/domain/repositories/history_repository.dart';

/// Everything the app does with the transfer log.
///
/// Grouped per capability rather than one class per verb: these are four
/// one-line delegations, and splitting them across four files would add
/// ceremony without adding a seam.
class HistoryUseCase {
  const HistoryUseCase(this._repository);

  final HistoryRepository _repository;

  Stream<List<TransferEvent>> watch() => _repository.watch();

  List<TransferEvent> current() => _repository.current;

  /// Called by the other features as their transfers finish.
  Future<void> record({
    required String name,
    required int bytes,
    required String peer,
    required bool incoming,
    required TransferWay way,
    /// Where the file is on this device, so the row can be opened later.
    String? path,
  }) => _repository.record(
    TransferEvent(
      name: name,
      bytes: bytes,
      peer: peer,
      incoming: incoming,
      way: way,
      at: DateTime.now(),
      path: path,
    ),
  );

  Future<void> clear() => _repository.clear();
}
