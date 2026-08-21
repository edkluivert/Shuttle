part of 'sharing_bloc.dart';

class SharingState extends Equatable {
  const SharingState({required this.status});

  final ServerStatus status;

  bool get isOnline => status.isRunning && status.addresses.isNotEmpty;

  SharingState copyWith({ServerStatus? status}) =>
      SharingState(status: status ?? this.status);

  @override
  List<Object?> get props => [status];
}
