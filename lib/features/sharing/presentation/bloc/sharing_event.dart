part of 'sharing_bloc.dart';

sealed class SharingEvent extends Equatable {
  const SharingEvent();

  @override
  List<Object?> get props => [];
}

/// Bring the server up. Sent once, by the shell, at launch.
class SharingStarted extends SharingEvent {
  const SharingStarted();
}

class SharingFilesAdded extends SharingEvent {
  const SharingFilesAdded(this.files);

  final List<File> files;

  @override
  List<Object?> get props => [files];
}

class SharingFileRemoved extends SharingEvent {
  const SharingFileRemoved(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}

class SharingCleared extends SharingEvent {
  const SharingCleared();
}

/// The repository reported new server state — a file taken, an upload
/// arrived, the address changed.
class SharingStatusChanged extends SharingEvent {
  const SharingStatusChanged(this.status);

  final ServerStatus status;

  @override
  List<Object?> get props => [status];
}
