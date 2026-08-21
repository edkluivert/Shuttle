import 'dart:async';

/// A stream that opens with the value something has *now*, then follows every
/// change to it — with no gap between the two.
///
/// The obvious spelling is an `async*` generator:
///
/// ```dart
/// Stream<T> watch() async* {
///   yield current;
///   yield* _controller.stream;
/// }
/// ```
///
/// which is quietly wrong. The generator body does not run when `listen` is
/// called — it runs a turn later — so anything emitted in between is lost,
/// and the first value the listener receives is whatever `current` had
/// already become. A screen that subscribed and immediately triggered a
/// change would miss its own change.
///
/// [Stream.multi] runs its callback synchronously on subscribe, so the
/// initial value and the subscription to [changes] happen in the same turn.
/// Each listener gets its own subscription, which is what a broadcast source
/// needs.
Stream<T> currentAndChanges<T>(T Function() current, Stream<T> changes) {
  return Stream<T>.multi((controller) {
    controller.add(current());

    final subscription = changes.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
}
