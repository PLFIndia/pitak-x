/// Loads one library's published catalogue for the viewer (network application
/// layer; ADR 0015, viewer plan S3).
///
/// Lifecycle contract (V12), all of it tested:
///  - one GET per mount: `build()` performs the only initial load;
///  - `refresh()` is the only other load and allows ONE request in flight (a
///    second request while one runs is ignored);
///  - every load carries a monotonic revision; a completion whose revision is
///    no longer the newest is dropped, so late bytes can never overwrite a
///    newer answer;
///  - disposal completes the caller-abort signal (the socket is closed by
///    `BoundedHttpFetcher`), supersedes the revision, and the viewer-owned
///    client is closed as the backstop by DI;
///  - NO repository, settings or descriptor write ever happens here (V15).
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_catalogue_use_case.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'published_catalogue_controller.g.dart';

/// The catalogue state for the library saved at `siteUrl`.
@riverpod
class PublishedCatalogueController extends _$PublishedCatalogueController {
  /// Monotonic load revision. Every completion publishes only if its revision
  /// is still current (the same N05 pattern as `LibraryController`).
  int _revision = 0;

  /// Caller-abort signal of the CURRENT load; completed on dispose/refresh.
  Completer<void>? _abort;

  /// The in-flight manual refresh, so concurrent calls collapse into one.
  Future<void>? _refreshing;

  /// Set when the notifier is disposed; a completion after that must not touch
  /// `state` (Riverpod throws once the element is gone).
  bool _disposed = false;

  /// The use case is captured in `build` from `ref.watch`, which both registers
  /// the dependency (keeping the fetcher/client alive) and gives `refresh` a
  /// stable reference.
  late LoadPublishedCatalogueUseCase _useCase;

  /// The family argument, which is only in scope inside `build`.
  late String _siteUrl;

  @override
  Future<PublishedCatalogue> build(String siteUrl) {
    _siteUrl = siteUrl;
    _disposed = false;
    _useCase = ref.watch(loadPublishedCatalogueUseCaseProvider(siteUrl));
    final abort = Completer<void>();
    _abort = abort;
    ref.onDispose(() {
      _disposed = true;
      _revision++; // every later completion is stale
      final signal = _abort;
      if (signal != null && !signal.isCompleted) signal.complete();
      _abort = null;
    });
    return _load(abort.future);
  }

  /// True when a deliberate reload would actually start now.
  ///
  /// Exposed because the page must coordinate two pieces of session state with
  /// one decision: it resets the cover session and then calls [refresh]. If the
  /// page guessed with its own conditions, the two could drift apart — that is
  /// exactly how a duplicate Reload tap could clear covers without adding a
  /// request (review finding 2). [refresh] enforces the SAME getter.
  bool get canRefresh => !_disposed && _refreshing == null && !state.isLoading;

  /// Reloads the catalogue deliberately.
  ///
  /// Returns the in-flight future when a manual reload is already running (one
  /// request maximum) and does nothing while the initial load still owns the
  /// request — see [canRefresh].
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) return running;
    if (!canRefresh) return Future<void>.value();
    final future = _refresh();
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    // A reload discards the old session's guarantee: abort whatever the old
    // signal still owns before starting a new request.
    final previous = _abort;
    if (previous != null && !previous.isCompleted) previous.complete();
    final abort = Completer<void>();
    _abort = abort;

    state = const AsyncLoading<PublishedCatalogue>().copyWithPrevious(state);
    final either = await _useCase(_siteUrl, abortTrigger: abort.future);
    if (_disposed || revision != _revision) return;
    state = either.match(
      (failure) => AsyncError<PublishedCatalogue>(failure, StackTrace.current),
      AsyncData<PublishedCatalogue>.new,
    );
  }

  /// The initial load. Throws the typed `Failure` so Riverpod surfaces a
  /// typed `AsyncError` (the repo's documented `only_throw_errors` pattern).
  Future<PublishedCatalogue> _load(Future<void> abort) async {
    final revision = ++_revision;
    final either = await _useCase(_siteUrl, abortTrigger: abort);
    if (_disposed || revision != _revision) {
      // Disposed/superseded: never resolve, so no stale value can land in a
      // newer session. The element is gone (or rebuilding), so nothing waits.
      return Completer<PublishedCatalogue>().future;
    }
    return either.fold(
      (failure) =>
          // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
          throw failure,
      (catalogue) => catalogue,
    );
  }
}
