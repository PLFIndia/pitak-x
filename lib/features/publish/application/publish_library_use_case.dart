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
///     never overwritten), persist the record, then read the live site back
///     (bounded) and record the result.
///
/// Cover images are downscaled by the injected local-cover reader
/// (`ImageDownscaler`, 400×600 q80 — the single image choke point), so a
/// publish uploads small JPEGs and EXIF/GPS never leaves the device.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/application/site/published_file_read_back.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

export 'publish_result.dart';

/// Coarse publish phases for the UI.
enum PublishPhase {
  /// Building books.json / viewer, deciding what changed.
  preparing,

  /// Creating blobs for changed files.
  uploading,

  /// Tree + commit + ref move.
  committing,

  /// Waiting for the live site to serve the new content (bounded).
  pagesBuilding,
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
    PublishedSiteVerifier? verifier,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _snapshotBuilder = snapshotBuilder,
       _reads = reads,
       _hostState = hostState,
       _verifier = verifier,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

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

  /// Records the verified live target after a read-back proves it (R33). The
  /// share/QR address never comes from this publish's own manifest.
  final PublishHostStateRecorder _hostState;

  /// Null ⇒ read-back skipped (tests / no network port wired).
  final PublishedSiteVerifier? _verifier;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  /// Repo-relative path of the network descriptor (docs/ARCHITECTURE.md §5.1).
  static const String libraryJsonPath = CatalogueSectionBuilder.libraryJsonPath;

  /// Runs the publish to [target].
  ///
  /// [target] is the EXACT destination of this operation (R1/C3). It is the
  /// only source of the site URL — for the descriptor, the read-back and the
  /// success message — so a move can publish the new site while the old one is
  /// still the active host.
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
  /// This path publishes the CATALOGUE section only. The events section has
  /// its own independent publish (`PublishEventsUseCase`, Q5=A), so this
  /// snapshot never carries poster files and can never delete one.
  Future<PublishResult> call({
    required GitHubPublishTarget target,
    PublishMode mode = PublishMode.incremental,
    void Function(PublishPhase)? onPhase,
  }) async {
    void phase(PublishPhase p) => onPhase?.call(p);
    phase(PublishPhase.preparing);

    final read = await _snapshotBuilder.read(
      reads: _reads,
      target: target,
      includeEvents: false,
    );
    final inputs = read.toNullable();
    if (inputs == null) {
      // A failed read is never "empty content": nothing is built or written.
      return PublishFailure(_messageFor(read.swap().toNullable()!));
    }

    final token = await _credentials.token();
    if (token == null) return const PublishFailure('Not signed in to GitHub.');
    // The target carries the address (derived, never supplied): no second
    // derivation here, so the descriptor, the commit and the read-back can
    // never disagree about where this publish goes.
    final owner = target.owner;
    final repo = target.repo;
    final pagesUrl = target.siteUrl;

    final now = _clock();

    // N09 (D2-a): commit to the branch Pages actually serves. Publishing to
    // any other branch would "succeed" without changing the live site.
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
    // it BEFORE building. Shas come from the tree (never from the local file),
    // and a path this phone did not write is never claimed — so `mergeSection`
    // below cannot delete a human's file, and an unchanged file is compared
    // against what the site really holds.
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
    // head we are about to build on, verify it first. A contradiction stops the
    // publish (a new commit would silently overwrite whatever changed the
    // site); an unreachable site does not, because a bad connection is not
    // evidence of a conflict.
    final verification = await _verifyUnconfirmed(
      local: localRecord,
      reconciled: previous,
      remoteHead: expectedHead,
      target: target,
      siteUrl: pagesUrl,
      anchorPath: CatalogueSectionBuilder.booksJsonPath,
      maxBytes: publishedCatalogueReadBackMaxBytes,
      revision: now,
    );
    if (verification == PublishVerificationOutcome.contradicted) {
      return const PublishFailure(gitHubSiteChangedSincePublishMessage);
    }

    // Phase 2: build the section through the SHARED builders (R3) against the
    // publication record that will also be merged, so change detection and
    // the merge can never disagree. A typed failure here means NOTHING was
    // written. The catalogue section owns no poster path, so a catalogue
    // publish can never delete one (R7).
    final built = await _snapshotBuilder.build(
      inputs: inputs,
      previous: previous,
      now: now,
      mode: mode,
    );
    final snapshot = built.toNullable();
    if (snapshot == null) {
      return PublishFailure(_messageFor(built.swap().toNullable()!));
    }
    final section = snapshot.catalogue;

    // R7: merge ONLY this section into the publication record. The events
    // section (and any other app-owned path) survives; the section's own
    // dropped paths become exact deletions (never a prefix sweep).
    final merge = mergeSection(previous: previous, section: section);

    phase(
      section.hasUploads ? PublishPhase.uploading : PublishPhase.committing,
    );

    final PublishCommitResult result;
    try {
      result = await _api.commitFiles(
        owner: owner,
        repo: repo,
        branch: branch,
        token: token,
        files: [
          for (final f in merge.files)
            DesiredFile(
              path: f.path,
              bytes: f.bytes,
              gitSha: f.gitSha,
              upload: f.upload,
            ),
        ],
        commitMessage: 'Pitaka publish $now',
        deletePaths: merge.deletePaths,
        expectedHead: expectedHead,
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const PublishFailure(gitHubNetworkErrorMessage);
    }

    switch (result) {
      case PublishCommitStale():
        // Another writer moved the branch after we read it (R6). Nothing was
        // written; the next publish starts from their newest state.
        return const PublishFailure(gitHubStalePublishMessage);
      case PublishCommitSuccess(:final uploadedPaths, :final commitSha):
        // R5/R9: persist the commit AS `deployed` before spending a minute on
        // read-back, so a crash here is recoverable instead of "unknown". A
        // failed save is reported, never swallowed: the site IS updated.
        final committed = previous.afterCommit(
          commitSha: commitSha,
          mergedShas: merge.fileShas,
          coverUrlByBookId: section.coverUrlByKey,
        );
        var localStateSaved = _manifest.save(committed).isRight();

        phase(PublishPhase.pagesBuilding);
        // Bounded read-back: poll the LIVE books.json with a cache-buster
        // until it serves exactly the bytes just published.
        final booksJson = merge.files
            .firstWhere((f) => f.path == CatalogueSectionBuilder.booksJsonPath)
            .bytes;
        final pagesLive = await _readBack(
          siteUrl: pagesUrl,
          path: CatalogueSectionBuilder.booksJsonPath,
          expected: booksJson,
          revision: now,
        );
        if (pagesLive ?? false) {
          // Proven live ⇒ the journal may now claim this address (R33). This
          // is the ONLY place the share/QR address is set by the catalogue
          // path, and it happens after the proof, never before.
          localStateSaved =
              (await _hostState.recordVerified(target)).isRight() &&
              localStateSaved;
          // The manifest upgrade is not reported on its own: a failure leaves
          // the record `deployed`, which is the truth (the commit landed, its
          // verification did not finish) and the next publish re-verifies it.
          _manifest.save(committed.asLive());
        }
        return PublishSuccess(
          pagesUrl: pagesUrl,
          uploadedPaths: uploadedPaths,
          availabilityOmitted: snapshot.availabilityOmitted,
          pagesLive: pagesLive,
          localStateSaved: localStateSaved,
        );
      case PublishCommitHttpError(:final code):
        // The response body is deliberately dropped: a hostile network can
        // inject arbitrary text into it (§5 "safe message only").
        return PublishFailure(gitHubHttpErrorMessage(code));
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

  /// Verifies an unconfirmed publication before building on it (F.4 step 2).
  ///
  /// A `matched` result upgrades the record to `live` and lets the journal
  /// claim the address (R33) — the same proof the post-publish read-back gives,
  /// just later. Both writes are best-effort: the publish continues either way,
  /// and a failed save leaves `deployed`, which is still the truth.
  Future<PublishVerificationOutcome> _verifyUnconfirmed({
    required PublishManifest local,
    required PublishManifest reconciled,
    required String remoteHead,
    required GitHubPublishTarget target,
    required String siteUrl,
    required String anchorPath,
    required int maxBytes,
    required int revision,
  }) async {
    final verifier = _verifier;
    if (verifier == null) return PublishVerificationOutcome.notApplicable;
    final outcome =
        await PublishVerificationCheck(verifier: verifier, sleep: _sleep).call(
          localState: local.state,
          localAnchor: local.headSha,
          remoteAnchor: remoteHead,
          expectedSha: reconciled.shaFor(anchorPath),
          siteUrl: siteUrl,
          anchorPath: anchorPath,
          maxBytes: maxBytes,
          revision: revision,
        );
    if (outcome == PublishVerificationOutcome.matched) {
      _manifest.save(reconciled.asLive());
      await _hostState.recordVerified(target);
    }
    return outcome;
  }

  /// Bounded origin-bound read-back of one just-published file.
  Future<bool?> _readBack({
    required String siteUrl,
    required String path,
    required List<int> expected,
    required int revision,
  }) async {
    final verifier = _verifier;
    if (verifier == null) return null;
    return PublishedFileReadBack(verifier: verifier, sleep: _sleep).untilServed(
      siteUrl: siteUrl,
      path: path,
      expected: expected,
      revision: revision,
    );
  }
}

/// Load/save view of the manifest the orchestrators need.
abstract interface class PublishManifestGateway {
  /// Loads the manifest (or empty).
  PublishManifest load();

  /// Persists [manifest]; a failure is returned, never swallowed (R9).
  Either<Failure, Unit> save(PublishManifest manifest);
}
