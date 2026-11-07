/// The single writer of `events_watch_state.json` inside one worker run
/// (PLAN.md §1 "serialized state reducer/commit queue").
///
/// How it works (beginner note): fetches for several libraries run at the
/// same time, and each finishes with a result. If every finishing fetch
/// read the state, changed it and wrote it back on its own, two of them
/// could overlap and one would overwrite the other's change. Instead, every
/// change goes through `commit`, which:
///  1. waits for the previous commit to finish (FIFO queue),
///  2. applies the change to the LATEST state (not a stale snapshot),
///  3. writes the file and waits for the write,
///  4. only then publishes the new state as `current`.
///
/// A failed write leaves `current` unchanged, so memory never claims more
/// than disk holds. After `stop`, every commit is refused: a fetch that
/// finishes after the deadline or after a stop marker cannot touch state.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';

/// A pure state transition. Must not perform IO.
typedef WatchStateMutation = EventsWatchState Function(EventsWatchState latest);

/// See the file header.
final class WatchStateReducer {
  /// Creates a reducer over [store], starting from [initial] (which the
  /// caller has already read from, or decided to replace in, the store).
  WatchStateReducer({
    required EventsWatchStateStore store,
    required EventsWatchState initial,
  }) : _store = store,
       _current = initial;

  final EventsWatchStateStore _store;
  final SerialOpQueue _queue = SerialOpQueue();
  EventsWatchState _current;
  bool _stopped = false;

  /// The latest state that is ALSO on disk.
  EventsWatchState get current => _current;

  /// True after [stop]; no further commits are accepted.
  bool get isStopped => _stopped;

  /// Applies [mutate] to the latest state, persists the result, publishes.
  ///
  /// Returns the committed state, or the write failure (state unchanged),
  /// or [StaleStateFailure] when the reducer was stopped — including when
  /// it was stopped while this commit was waiting in the queue.
  Future<Either<Failure, EventsWatchState>> commit(WatchStateMutation mutate) =>
      _queue.enqueue(() async {
        if (_stopped) return left(const StaleStateFailure('reducer stopped'));
        final next = mutate(_current);
        final written = await _store.write(next);
        return written.map((_) {
          _current = next;
          return next;
        });
      });

  /// Refuses every later commit. Commits already running finish; commits
  /// still queued are refused when their turn comes.
  void stop() => _stopped = true;
}
