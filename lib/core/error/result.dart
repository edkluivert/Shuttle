import 'package:shuttle/core/error/failure.dart';

/// Either a value or a [Failure], without a package to model it.
///
/// Dart 3's sealed classes and exhaustive switches cover what `Either` was
/// imported for, and read better at the call site: `switch (result) { Ok() =>
/// …, Err() => … }` needs no `fold` and no positional argument order to
/// remember.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;

  /// The value, or null when this failed — for the many call sites that treat
  /// a failure as "nothing came back".
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  R when<R>({
    required R Function(T value) ok,
    required R Function(Failure failure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
