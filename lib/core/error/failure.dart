import 'package:equatable/equatable.dart';

/// Why something did not work, in terms the presentation layer can act on.
///
/// Deliberately a small closed set: every failure here maps to a different
/// thing the UI says or offers, and one that does not is not worth its own
/// type.
sealed class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// The other device could not be reached, or stopped answering.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Could not reach that device.']);
}

/// A local file could not be read or written.
class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Could not read or write the file.']);
}

/// The helper a USB backend drives is missing, or the device is not there.
class DeviceFailure extends Failure {
  const DeviceFailure([super.message = 'No device is connected.']);
}

/// The user stopped it. Not an error, but it ends the operation, so it
/// travels the same path — the UI just stays quiet about it.
class CancelledFailure extends Failure {
  const CancelledFailure([super.message = 'Cancelled.']);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Something went wrong.']);
}
