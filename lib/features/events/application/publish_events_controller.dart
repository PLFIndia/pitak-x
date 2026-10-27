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
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
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
    // R1/C3: the operation's target is resolved ONCE, here, and passed in. The
    // use case never re-derives the repo, so a move can publish to the new
    // target while the old one is still active.
    final target = GitHubPublishTarget.create(await credentials.targetRepo());
    if (target == null) {
      return const PublishEventsFailure('Pick a target repo first.');
    }
    // N14: poster file IO arrives via DI (infrastructure port), keeping this
    // controller free of dart:io (§3.1).
    final readPoster = await ref.read(eventsPosterReaderProvider.future);
    final settings = await ref.read(settingsControllerProvider.future);
    final content = await ref.read(eventsControllerProvider.future);

    // The HTML factory is injected via DI (domain port) — the template load
    // (rootBundle) stays in infrastructure, wired by the composition root.
    final buildEventsHtml = ref.read(eventsHtmlFactoryProvider);
    final buildEventsJson = ref.read(eventsJsonFactoryProvider);
    // Bounded, origin-bound read-back (R16/F.4 step 7): an accepted commit is
    // not proof that the events page is served, so the record is only called
    // `live` after the live site proves it.
    final verifier = ref.read(publishedSiteVerifierProvider);
    final useCase = PublishEventsUseCase(
      api: api,
      target: target,
      credentials: credentials,
      manifest: manifest,
      readPoster: readPoster,
      buildEventsHtml: (posters) =>
          buildEventsHtml(libraryName: settings.libraryName, posters: posters),
      buildEventsJson: buildEventsJson,
      // Lazy: opened only once a read-back proves the page is served (R33).
      hostState: LazyPublishHostStateRecorder(
        () => ref.read(publishHostStateRepositoryProvider.future),
      ),
      verifier: verifier,
    );

    return useCase.call(content);
  }
}
