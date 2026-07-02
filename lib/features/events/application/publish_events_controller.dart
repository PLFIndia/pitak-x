/// Publish-events controller (application layer, AGENTS.md §4, #events).
///
/// Assembles [PublishEventsUseCase] from live providers and runs it on demand,
/// exposing an [AsyncValue] of the result. Reuses the catalogue's GitHub
/// credential, target repo, and publish manifest — the events publish is gated
/// on a prior catalogue publish inside the use case.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/events/application/events_controller.dart';
import 'package:pitaka/features/events/domain/poster_paths.dart';
import 'package:pitaka/features/publish/application/publish_events_use_case.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_events_controller.g.dart';

/// Runs an events publish and exposes its [PublishEventsResult].
@riverpod
class PublishEventsController extends _$PublishEventsController {
  @override
  FutureOr<PublishEventsResult?> build() => null;

  /// Publishes the current events content. Returns the result and stores it.
  Future<PublishEventsResult> publish() async {
    state = const AsyncLoading();
    try {
      final result = await _run();
      state = AsyncData(result);
      return result;
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<PublishEventsResult> _run() async {
    final api = ref.read(gitHubApiProvider);
    final credentials = ref.read(publishCredentialStoreProvider);
    final manifest = await ref.read(publishManifestStoreProvider.future);
    final dir = await ref.read(appDocsDirProvider.future);
    final settings = await ref.read(settingsControllerProvider.future);
    final content = await ref.read(eventsControllerProvider.future);

    // The HTML factory is injected via DI (domain port) — the template load
    // (rootBundle) stays in infrastructure, wired by the composition root.
    final buildEventsHtml = ref.read(eventsHtmlFactoryProvider);
    final useCase = PublishEventsUseCase(
      api: api,
      credentials: credentials,
      manifest: manifest,
      readPoster: (imageRef) => _readPoster(dir.path, imageRef),
      buildEventsHtml: (posters) =>
          buildEventsHtml(libraryName: settings.libraryName, posters: posters),
    );

    return useCase.call(content);
  }

  /// Reads a poster image's bytes from `<docs>/<imageRef>`, or null when the
  /// ref is not a `posters/…` leaf or the file is missing/unreadable.
  Future<List<int>?> _readPoster(String docsPath, String imageRef) async {
    // Only ever read inside the posters dir (defence against a crafted ref).
    final leaf = PosterPaths.leafOf(imageRef);
    if (leaf == null) return null;
    final file = File(p.join(docsPath, PosterPaths.postersDir, leaf));
    if (!file.existsSync()) return null;
    try {
      return await file.readAsBytes();
    } on Exception {
      return null;
    }
  }
}
