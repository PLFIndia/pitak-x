/// Screen-scoped availability state for the native saved-library viewer
/// (network application layer; ADR 0019 Decision 4, ADR 0015 amendment).
///
/// Two providers:
///  - [PublishedAvailabilityController] loads the optional
///    `availability.json`. Its lifecycle mirrors the events controller: one
///    load per mount, one manual refresh at a time, monotonic revisions,
///    caller abort on disposal, and no writes besides the saved copy
///    (ADR 0018). A null value means the library has no usable file.
///  - [publishedCatalogueWithAvailability] applies the ONE per-item rule
///    (`PublishedAvailabilityMerge`) to the loaded catalogue.
///
/// Why the catalogue never waits for the file (beginner note): both start
/// loading together when the page opens, in parallel. While the small file
/// is still on its way (or if it fails), items show their inline tags; when
/// it arrives the tags are re-decided. A slow or broken `availability.json`
/// can therefore never keep a reader from browsing the catalogue
/// (ADR 0015 amendment).
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_availability_merge.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_availability_use_case.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'published_availability_controller.g.dart';

/// The availability file state for the library saved at `siteUrl`.
@riverpod
class PublishedAvailabilityController
    extends _$PublishedAvailabilityController {
  int _revision = 0;
  Completer<void>? _abort;
  Future<void>? _refreshing;
  bool _disposed = false;
  late LoadPublishedAvailabilityUseCase _useCase;
  late String _siteUrl;

  @override
  Future<PublishedContent<PublishedAvailabilityFile>?> build(String siteUrl) {
    _siteUrl = siteUrl;
    _disposed = false;
    _useCase = ref.watch(loadPublishedAvailabilityUseCaseProvider(siteUrl));
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

  /// Whether a deliberate refresh can start now.
  bool get canRefresh => !_disposed && _refreshing == null && !state.isLoading;

  /// Reloads the file, collapsing duplicate requests into one.
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
    state = const AsyncLoading<PublishedContent<PublishedAvailabilityFile>?>()
        .copyWithPrevious(state);
    final either = await _useCase(_siteUrl, abortTrigger: abort.future);
    if (_disposed || revision != _revision) return;
    state = either.match(
      (failure) => AsyncError<PublishedContent<PublishedAvailabilityFile>?>(
        failure,
        StackTrace.current,
      ),
      AsyncData<PublishedContent<PublishedAvailabilityFile>?>.new,
    );
  }

  Future<PublishedContent<PublishedAvailabilityFile>?> _load(
    Future<void> abort,
  ) async {
    final revision = ++_revision;
    final either = await _useCase(_siteUrl, abortTrigger: abort);
    if (_disposed || revision != _revision) {
      // Disposed or superseded: never resolve, so no stale value can land
      // in a newer session.
      return Completer<PublishedContent<PublishedAvailabilityFile>?>().future;
    }
    return either.fold(
      // Riverpod surfaces typed failures through AsyncError; raw text is
      // never rendered by the UI.
      // ignore: only_throw_errors, typed Failure is Riverpod's error channel
      (failure) => throw failure,
      (content) => content,
    );
  }
}

/// The loaded catalogue with every item's tag decided by the ONE rule.
///
/// Watches the availability state as a plain value (never its `future`), so
/// a file that is still loading or that failed simply counts as "no file"
/// and the catalogue shows at once with its inline tags. A refresh keeps the
/// previous file until the new answer arrives (`valueOrNull`).
@riverpod
Future<PublishedCatalogueWithAvailability> publishedCatalogueWithAvailability(
  PublishedCatalogueWithAvailabilityRef ref,
  String siteUrl,
) async {
  // Watched BEFORE the catalogue is awaited, so the dependency (and the
  // file's load) never waits for the catalogue.
  final availability = ref.watch(
    publishedAvailabilityControllerProvider(siteUrl),
  );
  final catalogue = (await ref.watch(
    publishedCatalogueControllerProvider(siteUrl).future,
  )).value;
  final file = availability.valueOrNull?.value;
  return PublishedAvailabilityMerge.apply(
    catalogue: catalogue,
    file: file,
    nowMillis: ref.watch(clockProvider)(),
  );
}
