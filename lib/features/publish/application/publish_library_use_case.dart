/// Publish-to-GitHub-Pages orchestrator (application layer, AGENTS.md §4, #32).
///
/// Port of Kotlin `PublishLibraryUseCase`. Pushes the world-facing catalogue
/// (books.json + index.html viewer + library.json + salted covers/) as ONE
/// atomic, incremental commit via [GitHubGitDataApi] (the git-data role of
/// the GitHub port, S5 — this use case never touches auth or repo admin).
///
/// Pipeline:
///  1. Resolve token + target repo + the branch Pages SERVES from (N09: read
///     live from the Pages configuration, never assumed to be the default
///     branch; Pages off or re-pointed → typed failure before any write).
///  2. Reconcile the local record against the remote head + tree (R6): every
///     claimed sha comes from the tree, and foreign files are never adopted.
///  3. Ask the SHARED [PublishSnapshotBuilder] for the section to write
///     (Cloudflare plan R2/R3) — the same builder the Cloudflare adapter will
///     consume, over strict reads, so the two hosts cannot drift and a failed
///     read aborts before any write.
///  4. Merge that section into the publication record (R7): only its own
///     paths are replaced, the events section survives.
///  5. Commit the changed file set + exact owned deletions, passing the head
///     read in step 2 as `expectedHead` (a change made meanwhile is reported,
///     never overwritten), and persist the record as `deployed`. The commit's
///     `GitHubCommitPlan` sends only bytes the branch does not already hold
///     (CV5).
///  6. Return at once (plan SP1, ADR 0017 amendment of 2026-11-02). GitHub
///     Pages needs 36–42 s to rebuild the site; that wait no longer holds the
///     publish queue or the Publish button. The result carries a
///     `DeferredVerificationRequest`, and the controller proves the commit
///     live after the queue is released (`PublishGoingLive`). Nothing says
///     "live", and the share address is not recorded, before that proof.
///
/// Cover images are downscaled by the injected local-cover reader
/// (`ImageDownscaler`, 400×600 q80 — the single image choke point), so a
/// publish uploads small JPEGs and EXIF/GPS never leaves the device.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/application/github_unconfirmed_commit_check.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/deferred_verification_request.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

export 'publish_result.dart';

/// Coarse publish phases for the UI. There is no "waiting for Pages" phase
/// since plan SP1: the publish ends with the commit.
enum PublishPhase {
  /// Building books.json / viewer, deciding what changed.
  preparing,

  /// Creating blobs for changed files.
  uploading,

  /// Tree + commit + ref move.
  committing,
}

/// Orchestrates a single publish run.
final class PublishLibraryUseCase {
  /// Creates the use case over its ports.
  PublishLibraryUseCase({
    required GitHubGitDataApi api,
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PublishSnapshotBuilder snapshotBuilder,
    required PublishReads reads,
    required PublishHostStateRecorder hostState,
    PublishedSiteReadVerifier? reader,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
    PublishTimingSink? timingSink,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _snapshotBuilder = snapshotBuilder,
       _reads = reads,
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

  /// The ONE section builder for every host (R3). Building happens here, after
  /// the reconciled record is known, so exactly one read of the remote state
  /// feeds the change detection and the merge — the section is never built
  /// twice.
  final PublishSnapshotBuilder _snapshotBuilder;

  /// Strict typed reads the snapshot is built from (R2).
  final PublishReads _reads;

  /// The pre-publish check of this phone's unconfirmed commit, read through
  /// the proof that commit recorded (ADR 0019 Decision 10). It is also the
  /// only place this use case may record the verified address (R33): after
  /// it proves an EARLIER commit live.
  final GitHubUnconfirmedCommitCheck _unconfirmed;
  final int Function() _clock;

  /// Publish-timings sink (plan S0). Null in every normal build, so no stage
  /// is timed and nothing is logged; only `--dart-define=publishTimings=true`
  /// supplies one.
  final PublishTimingSink? _timingSink;

  /// Repo-relative path of the network descriptor (docs/ARCHITECTURE.md §5.1).
  static const String libraryJsonPath = CatalogueSectionBuilder.libraryJsonPath;

  /// Runs the publish to [target].
  ///
  /// [target] is the EXACT destination of this operation (R1/C3). It is the
  /// only source of the site URL — for the descriptor, the deferred check and
  /// the success message — so a move can publish the new site while the old
  /// one is still the active host.
  ///
  /// Phase 1 reads every input strictly through [_reads]. It runs FIRST, so a
  /// library that cannot be read fails before a token is fetched, before the
  /// GitHub API is called and before the manifest is loaded (R2: no remote
  /// write, and no pointless round trip, for a publish that cannot proceed).
  ///
  /// [mode] is [PublishMode.complete] for a move or a whole-site
  /// replacement: every required cover must then resolve to usable bytes, and
  /// a missing one fails typed BEFORE any write.
  ///
  /// This path publishes the CATALOGUE section, plus the AVAILABILITY section
  /// when `PublishReads.availability` asks for it (ADR 0019 Decision 6). The
  /// events section has its own independent publish (`PublishEventsUseCase`,
  /// Q5=A), so this snapshot never carries poster files and can never delete
  /// one.
  Future<PublishResult> call({
    required GitHubPublishTarget target,
    PublishMode mode = PublishMode.incremental,
    void Function(PublishPhase)? onPhase,
  }) async {
    // Plan S0: ONE recorder per publish. A null sink (release builds) turns the
    // whole recorder into a no-op, so no timing code runs there. `finally`
    // guarantees the line is emitted even when the publish fails early — a
    // failed publish is where the wasted time usually is.
    final timings = PublishTimingRecorder(
      sink: _timingSink,
      operation: 'catalogue',
      clock: _clock,
    );
    try {
      return await _run(
        target: target,
        mode: mode,
        onPhase: onPhase,
        timings: timings,
      );
    } finally {
      timings.finish();
    }
  }

  /// The publish pipeline itself.
  ///
  /// Timing note (plan S0): each stage is marked once, on its happy path, so a
  /// publish that fails early reports only the stages that actually ran. The
  /// marks never change behaviour — no wait, no read and no write depends on
  /// them.
  Future<PublishResult> _run({
    required GitHubPublishTarget target,
    required PublishMode mode,
    required void Function(PublishPhase)? onPhase,
    required PublishTimingRecorder timings,
  }) async {
    void phase(PublishPhase p) => onPhase?.call(p);
    phase(PublishPhase.preparing);

    final readStartedAt = timings.begin();
    final read = await _snapshotBuilder.read(
      reads: _reads,
      target: target,
      // This path owns the catalogue section only; the events section has its
      // own publish (fix-plan L6 reads exactly what is requested).
      sections: const {SiteSection.catalogue},
    );
    timings.end(PublishTimingStage.reads, readStartedAt);
    final inputs = read.toNullable();
    if (inputs == null) {
      // A failed read is never "empty content": nothing is built or written.
      return PublishFailure(_messageFor(read.swap().toNullable()!));
    }

    final token = await _credentials.token();
    if (token == null) return const PublishFailure('Not signed in to GitHub.');
    // The target carries the address (derived, never supplied): no second
    // derivation here, so the descriptor, the commit and the deferred check
    // can never disagree about where this publish goes.
    final owner = target.owner;
    final repo = target.repo;
    final pagesUrl = target.siteUrl;

    final now = _clock();

    // N09 (D2-a): commit to the branch Pages actually serves. Publishing to
    // any other branch would "succeed" without changing the live site.
    final reconcileStartedAt = timings.begin();
    final String branch;
    try {
      final site = await _api.pagesSite(owner: owner, repo: repo, token: token);
      if (site == null || !site.isPublishableByApp) {
        return const PublishFailure(gitHubPagesNotServingMessage);
      }
      branch = site.sourceBranch!;
    } on GitHubApiException {
      return const PublishFailure(gitHubNetworkErrorMessage);
    }

    // R6: read the remote head + tree and reconcile the local record against
    // it BEFORE building. Shas come from the tree (never from the local file
    // alone; plan SP4 skips the tree read only when a `live` record describes
    // exactly the current head, i.e. that same tree), and a path this phone
    // did not write is never claimed — so `mergeSection` below cannot delete a
    // human's file, and an unchanged file is compared against what the site
    // really holds.
    final localRecord = _manifest.load();
    final reconciliation = await GitHubPublicationReconciler(
      _api,
    ).call(target: target, branch: branch, token: token, local: localRecord);
    final publication = reconciliation.toNullable();
    if (publication == null) {
      return PublishFailure(_messageFor(reconciliation.swap().toNullable()!));
    }
    final previous = publication.manifest;
    final expectedHead = publication.headSha;

    // F.4 step 2 (deviation 48): if this phone has an UNCONFIRMED commit at the
    // head we are about to build on, verify it first, through the proof THAT
    // commit recorded (an events commit is proven by events.json, plan A.1
    // item 8). A contradiction stops the publish (a new commit would silently
    // overwrite whatever changed the site); an unreachable site does not,
    // because a bad connection is not evidence of a conflict.
    final verification = await _unconfirmed(
      local: localRecord,
      publication: publication,
      target: target,
      legacyProof: PublishProofPath.booksJson,
      revision: now,
      now: now,
    );
    timings.end(
      PublishTimingStage.reconcile,
      reconcileStartedAt,
      treeReads: publication.treeRead ? 1 : 0,
    );
    if (verification == PublishVerificationOutcome.contradicted) {
      return const PublishFailure(gitHubSiteChangedSincePublishMessage);
    }

    // Phase 2: build the section through the SHARED builders (R3) against the
    // publication record that will also be merged, so change detection and
    // the merge can never disagree. A typed failure here means NOTHING was
    // written. The catalogue section owns no poster path, so a catalogue
    // publish can never delete one (R7).
    final buildStartedAt = timings.begin();
    final built = await _snapshotBuilder.build(
      inputs: inputs,
      previous: previous,
      now: now,
      mode: mode,
      // Plan S0: the builder marks `coverDecisions` (nested inside this mark).
      timing: timings,
    );
    timings.end(PublishTimingStage.build, buildStartedAt);
    final snapshot = built.toNullable();
    if (snapshot == null) {
      return PublishFailure(_messageFor(built.swap().toNullable()!));
    }
    // The read above requested the catalogue, so it is present; a null here
    // would be a builder bug, and refusing is safer than publishing nothing.
    final section = snapshot.catalogue;
    if (section == null) {
      return const PublishFailure(PublishSnapshotBuilder.readFailedMessage);
    }

    // R7: merge ONLY this publish's sections into the publication record: the
    // catalogue, plus availability when the lane asks for it (ADR 0019
    // Decision 6: one commit, so the two never disagree). The events section
    // (and any other app-owned path) survives; each section's own dropped
    // paths become exact deletions (never a prefix sweep).
    final merge = mergeSections(
      previous: previous,
      sections: snapshot.sections,
    );
    // CV5 (ADR 0020 Decision 6): a file whose bytes the branch already holds,
    // at any path, is named by its sha instead of being sent again.
    final plan = GitHubCommitPlan(
      files: merge.files,
      knownBlobShas: publication.knownBlobShas,
    );

    phase(plan.hasUploads ? PublishPhase.uploading : PublishPhase.committing);

    // Bytes this commit will really upload: a file reused from the record or
    // already on the branch contributes nothing (plan S0 records the number,
    // it never changes it).
    final uploadBytes = timings.enabled ? plan.uploadBytes : null;
    final commitStartedAt = timings.begin();
    final PublishCommitResult result;
    try {
      result = await _api.commitFiles(
        owner: owner,
        repo: repo,
        branch: branch,
        token: token,
        plan: plan,
        commitMessage: 'Pitaka publish $now',
        deletePaths: merge.deletePaths,
        expectedHead: expectedHead,
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const PublishFailure(gitHubNetworkErrorMessage);
    }
    // GitHub uploads blobs inside commitFiles, so one mark carries both the
    // upload and the commit (`bytes` says how much of it was upload).
    timings.end(PublishTimingStage.commit, commitStartedAt, bytes: uploadBytes);

    switch (result) {
      case PublishCommitStale():
        // Another writer moved the branch after we read it (R6). Nothing was
        // written; the next publish starts from their newest state.
        return const PublishFailure(gitHubStalePublishMessage);
      case PublishCommitSuccess(:final uploadedPaths, :final commitSha):
        // R5/R9: persist the commit AS `deployed`: accepted, not yet seen
        // live. A failed save is reported, never swallowed: the site IS
        // updated.
        final committed = previous.afterCommit(
          commitSha: commitSha,
          mergedShas: merge.fileShas,
          coverUrlByBookId: section.coverUrlByKey,
          coverRendition: section.coverRendition,
          // The books.json just committed carries this phone's item keys
          // (ADR 0019 Decision 7b), so the lane may later publish against it.
          wroteKeyedCatalogue: snapshot.writesKeyedCatalogue,
          // Every catalogue commit changes books.json (`exportedAt`), so that
          // file proves it, also when availability.json rode along.
          proofPath: PublishProofPath.booksJson,
          // The clock AFTER the commit: a paced upload can take minutes, and
          // the Pages build window starts now (plan SP1).
          committedAt: _clock(),
        );
        final localStateSaved = _manifest.save(committed).isRight();
        // Plan SP1: no waiting for Pages here. The deferred check proves the
        // commit after the queue is released; without a saved record there
        // is nothing it could upgrade, and the next publish's pre-check
        // settles the commit instead.
        return PublishSuccess(
          pagesUrl: pagesUrl,
          uploadedPaths: uploadedPaths,
          availabilityOmitted: snapshot.availabilityOmitted,
          localStateSaved: localStateSaved,
          verification: localStateSaved
              ? DeferredVerificationRequest.forRecord(
                  target: target,
                  record: committed,
                  revision: now,
                )
              : null,
        );
      case PublishCommitHttpError(:final code):
        // The response body is deliberately dropped: a hostile network can
        // inject arbitrary text into it (§5 "safe message only").
        return PublishFailure(gitHubHttpErrorMessage(code));
      case final PublishCommitRateLimited limited:
        // GitHub's limit stopped the upload, or its pause is still on (plan
        // J8). Nothing was committed; what GitHub accepted is remembered, so
        // the next publish continues from there.
        return PublishFailure(gitHubRateLimitedMessage(limited));
    }
  }

  /// Maps a typed failure to the fixed, user-facing publish message.
  static String _messageFor(Failure failure) => switch (failure) {
    // A read failure carries its own already-safe sentence (M14: "could not
    // read your saved libraries" must not become a generic message).
    PublishReadFailure(:final message) => message,
    ValidationFailure(:final message) => message,
    _ => 'Something went wrong. Nothing was published.',
  };
}

/// Load/save view of the manifest the orchestrators need.
abstract interface class PublishManifestGateway {
  /// Loads the manifest (or empty).
  PublishManifest load();

  /// Persists [manifest]; a failure is returned, never swallowed (R9).
  Either<Failure, Unit> save(PublishManifest manifest);
}
