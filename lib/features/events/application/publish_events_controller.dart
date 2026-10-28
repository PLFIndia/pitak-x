/// Host-neutral events publish controller (application layer, AGENTS.md §4).
///
/// The journal selects GitHub or Cloudflare freshly inside the shared queue.
/// GitHub keeps its anchored commit use case; Cloudflare consumes the SAME
/// strict snapshot/replacement factory as catalogue. Expected outcomes use the
/// shared [PublishResult] so one replacement dialog works from either screen.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_controller.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_events_use_case.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_events_controller.g.dart';

/// Runs an events publish and exposes its shared [PublishResult].
@riverpod
class PublishEventsController extends _$PublishEventsController {
  @override
  FutureOr<PublishResult?> build() {
    // Keep the strict-read provider alive for the whole events operation. This
    // is only its PublishReads port; no nested publish/queue command is called.
    ref.listen(publishControllerProvider, (_, _) {});
    return null;
  }

  /// Publishes or confirms/retry-verifies the current events content.
  Future<PublishResult> publish({
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    final link = ref.keepAlive();
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(publishOperationQueueProvider)
          .enqueue(
            () => _run(
              confirmation: confirmation,
              verificationOnly: verificationOnly,
            ),
          );
      state = AsyncData(result);
      return result;
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      link.close();
    }
  }

  Future<PublishResult> _run({
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    final resolver = await ref.read(activePublishTargetResolverProvider.future);
    final resolved = await resolver.call();
    final targetFailure = resolved.swap().toNullable();
    if (targetFailure != null) {
      return CloudflarePublishOutcomes.failure(targetFailure);
    }
    final target = resolved.toNullable()!;
    if (target is GitHubPublishTarget &&
        (confirmation != null || verificationOnly)) {
      return const PublishFailure(
        'The publishing host changed before this command could continue.',
      );
    }
    return switch (target) {
      final GitHubPublishTarget gitHub => _runGitHub(gitHub),
      final CloudflarePublishTarget cloudflare => _runCloudflare(
        cloudflare,
        confirmation: confirmation,
        verificationOnly: verificationOnly,
      ),
    };
  }

  Future<PublishResult> _runCloudflare(
    CloudflarePublishTarget target, {
    PublishReplacementSummary? confirmation,
    bool verificationOnly = false,
  }) async {
    final factory = await ref.read(publishToCloudflareUseCaseProvider.future);
    final result = await factory(ref.read(publishControllerProvider.notifier))
        .call(
          target: target,
          section: PublishRequestedSection.events,
          confirmation: confirmation,
          verificationOnly: verificationOnly,
        );
    if (result is PublishSuccess) {
      ref
        ..invalidate(publishedSiteUrlProvider)
        ..invalidate(cloudflareConnectionControllerProvider);
    }
    return result;
  }

  Future<PublishResult> _runGitHub(GitHubPublishTarget target) async {
    // The strict publish read is deliberately NOT the tolerant editor read:
    // corrupt events metadata must never become an empty public events page.
    final stored = await (await ref.read(
      eventsRepositoryProvider.future,
    )).loadStrict();
    final content = stored.toNullable();
    if (content == null) {
      return const PublishFailure(PublishSnapshotBuilder.readFailedMessage);
    }

    final api = ref.read(gitHubApiProvider);
    final credentials = ref.read(publishCredentialStoreProvider);
    final manifest = await ref.read(publishManifestStoreProvider.future);
    final readPoster = await ref.read(eventsPosterReaderProvider.future);
    final settings = await ref.read(settingsControllerProvider.future);
    final buildEventsHtml = ref.read(eventsHtmlFactoryProvider);
    final buildEventsJson = ref.read(eventsJsonFactoryProvider);
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
      hostState: LazyPublishHostStateRecorder(
        () => ref.read(publishHostStateRepositoryProvider.future),
      ),
      verifier: verifier,
    );

    final result = await useCase.call(content);
    final mapped = switch (result) {
      final PublishEventsSuccess success => PublishSuccess(
        pagesUrl: success.eventsUrl,
        uploadedPaths: success.uploadedPaths,
        pagesLive: success.pagesLive,
        localStateSaved: success.localStateSaved,
      ),
      PublishEventsFailure(:final reason) => PublishFailure(reason),
    };
    if (mapped is PublishSuccess) ref.invalidate(publishedSiteUrlProvider);
    return mapped;
  }
}
