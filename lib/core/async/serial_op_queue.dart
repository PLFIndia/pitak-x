/// Serializes asynchronous operations of one owner so two UI actions can never
/// interleave writes (core utility; the vault and the publish queue share it).
///
/// Why: the Rust core re-derives the vault key per call, so interleaving two
/// vault operations doubles the KDF cost and races the re-read; a publish has
/// the same "one writer per target" requirement (Cloudflare plan M30/C6). A
/// plain Dart object — unit-testable without any IO or Riverpod, and free of
/// nesting: only the OUTERMOST command enqueues (a nested enqueue would
/// deadlock behind its own caller).
///
/// `core/async` rather than a feature folder because more than one feature
/// needs it; putting it under `vault` would make publishing import vault.
///
/// Errors must not break the chain: the tail completer is completed in a
/// `finally` (never with an error), so a failed op propagates to ITS caller
/// only and the next queued op still runs. Adapted from synchronized's
/// BasicLock (completer released in finally); no new dependency is needed.
library;

import 'dart:async';

/// See the file header.
final class SerialOpQueue {
  Future<void>? _tail;

  /// Runs [op] after every previously enqueued op has completed (FIFO).
  /// Whatever [op] returns or throws goes to its own caller only.
  Future<T> enqueue<T>(Future<T> Function() op) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      // Never throws: the tail future is always completed NORMALLY (see
      // finally), so a failed predecessor cannot block or poison us.
      if (previous != null) await previous;
      return await op();
    } finally {
      // Clear the tail only if nobody queued behind us (their enqueue
      // already replaced _tail with their own completer).
      if (identical(_tail, done.future)) _tail = null;
      done.complete();
    }
  }
}
