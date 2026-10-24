import 'dart:async';

/// A one-shot, controllable asynchronous response for race-regression tests.
///
/// The operation under test awaits [wait]. The test can await [entered] to
/// prove that operation really started, then choose its result with [succeed]
/// or [fail]. Create a new gate for each operation or prefill generation.
final class AsyncValueGate<T> {
  final Completer<void> _entered = Completer<void>();
  final Completer<T> _response = Completer<T>();

  /// Completes when the asynchronous operation first waits on this gate.
  Future<void> get entered => _entered.future;

  /// Parks the operation until the test supplies a response.
  Future<T> wait() {
    if (!_entered.isCompleted) _entered.complete();
    return _response.future;
  }

  /// Lets the parked operation finish successfully with [value].
  void succeed(T value) => _response.complete(value);

  /// Lets the parked operation finish with an expected test failure.
  void fail(Object error, [StackTrace? stackTrace]) =>
      _response.completeError(error, stackTrace);
}
