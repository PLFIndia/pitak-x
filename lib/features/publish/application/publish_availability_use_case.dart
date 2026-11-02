/// Publishes ONLY `availability.json` to GitHub Pages (application layer;
/// ADR 0019 Decisions 7 and 10, plan AV10/AV12/C.5).
///
/// This is the GitHub half of the availability lane: after a loan, the lane
/// (plan S6) hands it a saved "not available" set, or a removal when the
/// switch is off, and this use case commits that one file. It reads no loans,
/// builds no catalogue and touches no cover, which is what makes it cheap
/// enough to run after every loan.
///
/// It is modelled on the events publish and shares its building blocks (one
/// blessed way, G2): the same reconciler, the same section merge, the same
/// anchored commit, and the same pre-check of an unconfirmed earlier commit.
///
/// Pipeline:
///  1. token, and the branch Pages actually serves (N09);
///  2. reconcile the local record against the remote head + tree (R6);
///  3. gate 7b, for a write: the live `books.json` must be this phone's own
///     keyed publish. `reconciledFrom` keeps `catalogueKeyed` only while the
///     branch holds exactly the `books.json` this phone recorded, so that
///     flag IS the whole GitHub half of the gate. A removal needs no gate:
///     deleting the file is always the safe direction (readers fall back to
///     the inline tag), and only a recorded, still-present file is deleted;
///  4. verify an unconfirmed earlier commit through ITS proof (plan A.1
///     item 8);
///  5. build the section; if it changes nothing, commit nothing;
///  6. commit with `expectedHead` (a change made meanwhile is reported, never
///     overwritten);
///  7. save the record as `deployed` with its proof path and return "going
///     live". There is NO waiting for Pages inside the publish queue: the
///     caller runs `DeferredPublishVerification` after the queue is released.
///
/// Gates (a) "an active, connected host with a resolved target" and (c) "an
/// ordinary publish would be allowed now (no pending move)" belong to the
/// caller: it resolves [GitHubPublishTarget] inside the publish queue through
/// `ActivePublishTargetResolver`, which refuses both, exactly as the
/// catalogue and events commands do. This use case never re-derives the
/// target (R1/C3).
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/application/github_unconfirmed_commit_check.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

/// Orchestrates one availability-only GitHub publish.
final class PublishAvailabilityUseCase {
  /// Creates the use case over its ports.
  ///
  /// [reader] is used only for the pre-check of an earlier unconfirmed commit;
  /// null skips it (tests / no network port wired), as in the other publishes.
  PublishAvailabilityUseCase({
    required GitHubGitDataApi api,
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PublishHostStateRecorder hostState,
    PublishedSiteReadVerifier? reader,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
    PublishTimingSink? timingSink,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _unconfirmed = GitHubUnconfirmedCommitCheck(
         reader: reader,
         manifest: manifest,
         hostState: hostState,
         sleep: sleep ?? Future<void>.delayed,
       ),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _timingSink = timingSink;

  final GitHubGitDataApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final GitHubUnconfirmedCommitCheck _unconfirmed;
  final int Function() _clock;

  /// Publish-timings sink (plan S0). Null in every normal build; only
  /// `--dart-define=publishTimings=true` supplies one (plan S8 measures the
  /// lane with it).
  final PublishTimingSink? _timingSink;

  /// Publishes [update] to [target], the EXACT destination resolved by the
  /// caller inside the publish queue.
  Future<AvailabilityPublishResult> call({
    required GitHubPublishTarget target,
    required AvailabilityUpdate update,
  }) async {
    // One recorder per publish; a null sink makes every mark a no-op, and
    // `finally` emits the line on failure paths too (plan S0).
    final timings = PublishTimingRecorder(
      sink: _timingSink,
      operation: 'availability',
      clock: _clock,
    );
    try {
      return await _run(target: target, update: update, timings: timings);
    } finally {
      timings.finish();
    }
  }

  Future<AvailabilityPublishResult> _run({
    required GitHubPublishTarget target,
    required AvailabilityUpdate update,
    required PublishTimingRecorder timings,
  }) async {
    final token = await _credentials.token();
    if (token == null) {
      return const AvailabilityPending('Not signed in to GitHub.');
    }
    final now = _clock();

    // N09 (D2-a): commit to the branch Pages actually serves.
    final reconcileStartedAt = timings.begin();
    final String branch;
    try {
      final site = await _api.pagesSite(
        owner: target.owner,
        repo: target.repo,
        token: token,
      );
      if (site == null || !site.isPublishableByApp) {
        return const AvailabilityPending(gitHubPagesNotServingMessage);
      }
      branch = site.sourceBranch!;
    } on GitHubApiException {
      return const AvailabilityPending(gitHubNetworkErrorMessage);
    }

    // R6: shas, ownership and `catalogueKeyed` come from the remote tree,
    // never from the local file alone.
    final localRecord = _manifest.load();
    final reconciliation = await GitHubPublicationReconciler(
      _api,
    ).call(target: target, branch: branch, token: token, local: localRecord);
    final publication = reconciliation.toNullable();
    if (publication == null) {
      return AvailabilityPending(
        _messageFor(reconciliation.swap().toNullable()!),
      );
    }
    final reconciled = publication.manifest;

    // Gate 7b (writes only; see the file header). Checked before any public
    // read, because nothing can be published here until a catalogue publish.
    if (update is AvailabilityWrite && !reconciled.catalogueKeyed) {
      // A file still on the branch was published against keys the live
      // books.json no longer carries; the lane removes it (plan S6).
      return AvailabilityNotReady(
        AvailabilityPublishMessages.catalogueNotKeyed,
        staleFileRecorded:
            AvailabilitySectionBuilder.removal(previous: reconciled) != null,
      );
    }

    // F.4 step 2: verify an unconfirmed commit at this head through the proof
    // it recorded. A record without a proof can only come from a build before
    // ADR 0019, whose last keyed commit was a catalogue commit.
    final verification = await _unconfirmed(
      local: localRecord,
      publication: publication,
      target: target,
      legacyProof: PublishProofPath.booksJson,
      revision: now,
    );
    timings.end(PublishTimingStage.reconcile, reconcileStartedAt);
    if (verification == PublishVerificationOutcome.contradicted) {
      return const AvailabilityPending(gitHubSiteChangedSincePublishMessage);
    }

    // The one availability section builder (S3): the file, marked for upload
    // only when its sha differs from the tree's; or the exact deletion, or
    // nothing when no file is recorded.
    final section = switch (update) {
      AvailabilityWrite(:final snapshot) => AvailabilitySectionBuilder.write(
        snapshot: snapshot,
        previous: reconciled,
      ),
      AvailabilityDelete() => AvailabilitySectionBuilder.removal(
        previous: reconciled,
      ),
    };
    if (section == null || !section.changesSite) {
      // A commit that changes nothing would still cost a Pages build and one
      // of the ~10 builds per hour (AV6), so none is made.
      return const AvailabilityAlreadyPublished();
    }
    final merge = mergeSections(previous: reconciled, sections: [section]);
    final proof = switch (update) {
      AvailabilityWrite() => PublishProofPath.availabilityJson,
      AvailabilityDelete() => PublishProofPath.availabilityJsonAbsent,
    };

    // CV5 (ADR 0020 Decision 6): the one rule for what a commit sends.
    final plan = GitHubCommitPlan(
      files: merge.files,
      knownBlobShas: publication.knownBlobShas,
    );

    final commitStartedAt = timings.begin();
    final PublishCommitResult result;
    try {
      result = await _api.commitFiles(
        owner: target.owner,
        repo: target.repo,
        branch: branch,
        token: token,
        plan: plan,
        deletePaths: merge.deletePaths,
        commitMessage: 'Pitak availability update $now',
        expectedHead: publication.headSha,
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const AvailabilityPending(gitHubNetworkErrorMessage);
    }
    timings.end(
      PublishTimingStage.commit,
      commitStartedAt,
      bytes: timings.enabled ? plan.uploadBytes : null,
    );

    switch (result) {
      case PublishCommitStale():
        // Another writer moved the branch after our read (R6). Nothing was
        // written; the next attempt starts from a fresh reconcile.
        return const AvailabilityPending(
          AvailabilityPublishMessages.siteMovedOn,
        );
      case PublishCommitHttpError(:final code):
        // The response body is dropped: it may carry injected text (§5).
        return AvailabilityPending(gitHubHttpErrorMessage(code));
      case PublishCommitRateLimited():
        // GitHub's pause (plan J8): the lane's backoff tries again later, and
        // until the pause ends that try sends nothing.
        return const AvailabilityPending(gitHubPausedMessage);
      case PublishCommitSuccess(:final commitSha):
        // R5/R9: `deployed` with the proof of THIS commit. The catalogue's
        // books.json is unchanged, so `catalogueKeyed` carries over.
        final committed = reconciled.afterCommit(
          commitSha: commitSha,
          mergedShas: merge.fileShas,
          coverUrlByBookId: reconciled.coverUrlByBookId,
          coverRendition: reconciled.coverRendition,
          proofPath: proof,
        );
        final saved = _manifest.save(committed).isRight();
        return AvailabilityGoingLive(
          acceptedAt: now,
          localStateSaved: saved,
          // Without a saved record there is nothing a deferred check could
          // upgrade; the next publish's pre-check settles the commit.
          verification: saved
              ? DeferredVerificationRequest.forRecord(
                  target: target,
                  record: committed,
                  revision: now,
                )
              : null,
        );
    }
  }

  /// Maps a reconcile failure to its fixed, user-facing message.
  static String _messageFor(Failure failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    _ => gitHubSiteStateUnreadableMessage,
  };
}
