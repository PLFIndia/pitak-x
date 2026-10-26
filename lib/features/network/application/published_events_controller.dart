/// Screen-scoped public-events state for the native saved-library viewer.
///
/// Lifecycle mirrors the catalogue controller: one load per mount, one manual
/// refresh at a time, monotonic revisions, caller abort on disposal, and no
/// persistence or writes. A null value means the optional file is absent.
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_events_use_case.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'published_events_controller.g.dart';

/// The public events state for the library saved at `siteUrl`.
@riverpod
class PublishedEventsController extends _$PublishedEventsController {
  int _revision = 0;
  Completer<void>? _abort;
  Future<void>? _refreshing;
  bool _disposed = false;
  late LoadPublishedEventsUseCase _useCase;
  late String _siteUrl;

  @override
  Future<PublishedEvents?> build(String siteUrl) {
    _siteUrl = siteUrl;
    _disposed = false;
    _useCase = ref.watch(loadPublishedEventsUseCaseProvider(siteUrl));
    final abort = Completer<void>();
    _abort = abort;
    ref.onDispose(() {
      _disposed = true;
      _revision++;
      final signal = _abort;
      if (signal != null && !signal.isCompleted) signal.complete();
      _abort = null;
    });
    return _load(abort.future);
  }

  /// Whether a deliberate refresh can start now.
  bool get canRefresh => !_disposed && _refreshing == null && !state.isLoading;

  /// Reloads the optional events file, collapsing duplicate requests.
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
    final previous = _abort;
    if (previous != null && !previous.isCompleted) previous.complete();
    final abort = Completer<void>();
    _abort = abort;
    state = const AsyncLoading<PublishedEvents?>().copyWithPrevious(state);
    final either = await _useCase(_siteUrl, abortTrigger: abort.future);
    if (_disposed || revision != _revision) return;
    state = either.match(
      (failure) => AsyncError<PublishedEvents?>(failure, StackTrace.current),
      AsyncData<PublishedEvents?>.new,
    );
  }

  Future<PublishedEvents?> _load(Future<void> abort) async {
    final revision = ++_revision;
    final either = await _useCase(_siteUrl, abortTrigger: abort);
    if (_disposed || revision != _revision) {
      return Completer<PublishedEvents?>().future;
    }
    return either.fold(
      // Riverpod surfaces typed failures through AsyncError; raw text is never
      // rendered by the UI.
      // ignore: only_throw_errors, typed Failure is Riverpod's error channel
      (failure) => throw failure,
      (events) => events,
    );
  }
}
