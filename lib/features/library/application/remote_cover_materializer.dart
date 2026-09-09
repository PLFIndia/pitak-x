/// Session-wide scheduler for remote-cover downloads (M09).
///
/// The `BookCover` widget calls `request` when asked to show a book whose
/// cover is an allow-listed `https://` URL. This notifier is the single gate
/// between that UI event and any network packet:
///
///  1. **Consent** — nothing happens unless `AppSettings.loadRemoteCovers`
///     is `true` *and known*. While settings are still loading, or if they
///     failed to load, the request is dropped (fail closed, never queued for
///     later — the user's intent is not known).
///  2. **Once per book per app run** — a row scrolling past fifty times is
///     one download, and a failed download is not retried until the next
///     app start (a poisoned-but-allow-listed URL cannot be used to keep the
///     device talking to that host).
///  3. **One at a time** — downloads run through a FIFO so a long import
///     with hundreds of remote covers never opens hundreds of sockets or
///     buffers hundreds of images at once.
///  4. After a successful materialisation the library list is refreshed so
///     the new local file replaces the placeholder.
///
/// keepAlive: the dedup set and the queue must outlive any single screen —
/// an autoDispose provider would forget what it already fetched every time the
/// list rebuilt. Exposes no state to the UI (`build` returns nothing).
///
/// Serialisation pattern adapted from this repo's `CoverFileCoordinator`
/// (itself from synchronized's BasicLock, MIT).
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_cover_materializer.g.dart';

/// Schedules at-most-once, serialised remote-cover downloads for the session.
@Riverpod(keepAlive: true)
class RemoteCoverMaterializer extends _$RemoteCoverMaterializer {
  /// Book ids already scheduled this app run (in flight, done, or failed).
  final Set<int> _seen = {};

  /// Tail of the FIFO; null when idle.
  Future<void>? _tail;

  @override
  void build() {
    // No initial work and no observable state; the notifier is a scheduler.
  }

  /// Asks for [bookId]'s remote cover to be downloaded and stored locally.
  /// Cheap and idempotent — safe to call from a widget's post-frame callback.
  void request(int bookId) {
    // Consent gate: read, not watch — a consent flip must not replay every
    // request the UI ever made; the next display will ask again.
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings == null || !settings.loadRemoteCovers) return;
    if (!_seen.add(bookId)) return;
    _enqueue(bookId);
  }

  void _enqueue(int bookId) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    unawaited(() async {
      try {
        if (previous != null) await previous;
        await _materialize(bookId);
      } finally {
        if (identical(_tail, released.future)) _tail = null;
        released.complete();
      }
    }());
  }

  Future<void> _materialize(int bookId) async {
    final useCase = await ref.read(
      materializeRemoteCoverUseCaseProvider.future,
    );
    final result = await useCase(bookId);
    // A failure leaves the URL in place and the placeholder showing; the row
    // stays in `_seen` so this session does not hammer the host. Nothing to
    // show the user: a missing thumbnail is not an error they can act on.
    if (result.isRight()) ref.invalidate(libraryControllerProvider);
  }

  /// Test seam: completes when every download requested so far has finished.
  /// Production code has no reason to await this.
  Future<void> get idle => _tail ?? Future.value();
}
