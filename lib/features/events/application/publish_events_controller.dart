/// Publish-events controller (application layer, AGENTS.md §4, #events).
///
/// Assembles [PublishEventsUseCase] from live providers and runs it on demand,
/// exposing an [AsyncValue] of the result. Reuses the catalogue's GitHub
/// credential, target repo, and publish manifest — the events publish is gated
/// on a prior catalogue publish inside the use case.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/events/application/events_controller.dart';
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
    // N14: poster file IO arrives via DI (infrastructure port), keeping this
    // controller free of dart:io (§3.1).
    final readPoster = await ref.read(eventsPosterReaderProvider.future);
    final settings = await ref.read(settingsControllerProvider.future);
    final content = await ref.read(eventsControllerProvider.future);

    // The HTML factory is injected via DI (domain port) — the template load
    // (rootBundle) stays in infrastructure, wired by the composition root.
    final buildEventsHtml = ref.read(eventsHtmlFactoryProvider);
    final useCase = PublishEventsUseCase(
      api: api,
      credentials: credentials,
      manifest: manifest,
      readPoster: readPoster,
      buildEventsHtml: (posters) =>
          buildEventsHtml(libraryName: settings.libraryName, posters: posters),
    );

    return useCase.call(content);
  }
}
