/// Publish-events orchestrator (application layer, AGENTS.md §4, #events).
///
/// A SELF-CONTAINED publish path for the events page, independent of the
/// catalogue publish (Q5=A): the library can update/clear its posters without
/// re-publishing the book list, and vice versa. It pushes `events.html`, the
/// machine-readable `events.json`, and the poster images as ONE atomic
/// incremental commit via [GitHubGitDataApi] (the git-data role of the GitHub
/// port, S5).
///
/// The TARGET is resolved by the caller (the controller) and passed in — this
/// use case never re-derives the repo from credentials (R1/C3). That is the
/// same rule the catalogue publish follows, and it is what lets a move publish
/// to the NEW target while the old one is still active.
///
/// Gate (Q8=A): refuses unless the on-device publish manifest proves the
/// catalogue was already published to the CURRENT target repo (it contains an
/// `index.html` entry for that repo). This keeps "the website exists" true
/// before we add a second page to it.
///
/// The section itself is built by the SHARED [EventsSectionBuilder] (Cloudflare
/// plan R3) and merged into the publication record with [mergeSection] (R7),
/// so publishing events can never drop the catalogue's file shas and publishing
/// the catalogue can never drop a poster.
///
/// Since schema 2 the commit is also anchored: the branch head is read before
/// building and passed back as `expectedHead`, so a commit made meanwhile is
/// reported as stale instead of overwritten (R6). Read-back then decides
/// whether the record may be called `live` — an accepted commit alone is not
/// proof that the page is served (F.4 step 7).
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/application/site/published_file_read_back.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_events_ports.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

/// Built once per call so the same poster-reader/html/json ports are used for
/// every poster.
///
/// Re-exported ports keep the existing imports working (see
/// `publish_library_use_case.dart` for the same compatibility rule).
export 'site/events_section_builder.dart'
    show EventsHtmlBuilderFn, PosterBytesReader;

/// Outcome of an events publish.
sealed class PublishEventsResult {
  const PublishEventsResult();
}

/// Publish succeeded; the events page is at [eventsUrl].
final class PublishEventsSuccess extends PublishEventsResult {
  /// Creates a success result.
  const PublishEventsSuccess({
    required this.eventsUrl,
    required this.uploadedPaths,
    this.localStateSaved = true,
    this.pagesLive,
  });

  /// Public URL of the events page.
  final String eventsUrl;

  /// Files whose bytes were uploaded this run.
  final List<String> uploadedPaths;

  /// False when the commit landed but this phone could not save its own record
  /// of the publish (R9). The site IS updated; the next publish reconciles.
  final bool localStateSaved;

  /// True only after exact read-back; null when verification did not finish.
  final bool? pagesLive;
}

/// Publish failed; [reason] is a safe, human-readable message.
final class PublishEventsFailure extends PublishEventsResult {
  /// Creates a failure result.
  const PublishEventsFailure(this.reason);

  /// Why it failed.
  final String reason;
}

/// Orchestrates a single events publish.
final class PublishEventsUseCase {
  /// Creates the use case over its ports.
  PublishEventsUseCase({
    required GitHubGitDataApi api,
    required GitHubPublishTarget target,
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PosterBytesReader readPoster,
    required EventsHtmlBuilderFn buildEventsHtml,
    required EventsJsonFactory buildEventsJson,
    required PublishPageSettings settings,
    required PublishHostStateRecorder hostState,
    PublishedSiteVerifier? verifier,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
  }) : _api = api,
       _target = target,
       _credentials = credentials,
       _manifest = manifest,
       _section = EventsSectionBuilder(
         readPoster: readPoster,
         buildEventsHtml: buildEventsHtml,
         buildEventsJson: buildEventsJson,
       ),
       _settings = settings,
       _hostState = hostState,
       _verifier = verifier,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubGitDataApi _api;

  /// The exact destination of THIS operation (R1/C3). Never re-derived.
  final GitHubPublishTarget _target;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final EventsSectionBuilder _section;
  final PublishPageSettings _settings;

  /// Records the verified live target after a read-back proves it (R33).
  final PublishHostStateRecorder _hostState;

  /// Null ⇒ read-back skipped (tests / no network port wired).
  final PublishedSiteVerifier? _verifier;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  /// Repo path of the catalogue page whose presence proves "already published".
  static const String _catalogueMarker = 'index.html';

  /// Runs the events publish for [content].
  ///
  /// [mode] is [PublishMode.complete] for a move or a whole-site replacement:
  /// a poster whose local bytes are unreadable then fails typed BEFORE any
  /// write instead of being dropped.
  Future<PublishEventsResult> call(
    EventsContent content, {
    PublishMode mode = PublishMode.incremental,
  }) async {
    final token = await _credentials.token();
    if (token == null) {
      return const PublishEventsFailure('Not signed in to GitHub.');
    }
    final target = _target;
    final owner = target.owner;
    final repo = target.repo;
    // N09: ONE resolver for every published address (user site vs project
    // site) — the target's canonical root, so a user site and a project site
    // both resolve correctly and no second derivation exists.
    final eventsUrl = '${target.siteUrl}events.html';

    // N09 (D2-a): commit to the branch Pages actually serves (see the
    // catalogue use case for the reasoning).
    final String branch;
    try {
      final site = await _api.pagesSite(owner: owner, repo: repo, token: token);
      if (site == null || !site.isPublishableByApp) {
        return const PublishEventsFailure(gitHubPagesNotServingMessage);
      }
      branch = site.sourceBranch!;
    } on GitHubApiException {
      return const PublishEventsFailure(gitHubNetworkErrorMessage);
    }

    // R6: shas and ownership come from the remote tree, never from the local
    // file. That is also what makes the catalogue gate below trustworthy: a
    // claimed `index.html` means the file really exists on the site.
    final localRecord = _manifest.load();
    final reconciliation = await GitHubPublicationReconciler(
      _api,
    ).call(target: target, branch: branch, token: token, local: localRecord);
    final publication = reconciliation.toNullable();
    if (publication == null) {
      return PublishEventsFailure(switch (reconciliation.swap().toNullable()!) {
        ValidationFailure(:final message) => message,
        _ => 'Something went wrong. Nothing was published.',
      });
    }
    final manifest = publication.manifest;

    // F.4 step 2 (deviation 48): verify an unconfirmed commit at this head
    // before building on it. Contradiction stops; unreachable does not.
    final verification = await _verifyUnconfirmed(
      local: localRecord,
      reconciled: manifest,
      remoteHead: publication.headSha,
      target: target,
      siteUrl: target.siteUrl,
      revision: _clock(),
    );
    if (verification == PublishVerificationOutcome.contradicted) {
      return const PublishEventsFailure(gitHubSiteChangedSincePublishMessage);
    }

    // Gate (Q8=A): the catalogue must have been published to THIS repo.
    if (manifest.repo != target.ownerRepo ||
        manifest.shaFor(_catalogueMarker) == null) {
      return const PublishEventsFailure(
        'Publish your catalogue first, then publish events.',
      );
    }

    // Build the section with the SHARED builder: one filtered poster list
    // feeds HTML, JSON and the uploads, so unreadable posters can never
    // appear in one representation but not another.
    final built = await _section.build(
      content: content,
      settings: _settings,
      previous: manifest,
      mode: mode,
    );
    final failure = built.swap().toNullable();
    if (failure != null) {
      return PublishEventsFailure(switch (failure) {
        ValidationFailure(:final message) => message,
        _ => 'Something went wrong. Nothing was published.',
      });
    }
    final section = built.toNullable()!;
    final merge = mergeSection(previous: manifest, section: section);

    final now = _clock();
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
        deletePaths: merge.deletePaths,
        commitMessage: 'Pitak events publish $now',
        expectedHead: publication.headSha,
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const PublishEventsFailure(gitHubNetworkErrorMessage);
    }

    switch (result) {
      case PublishCommitStale():
        return const PublishEventsFailure(gitHubStalePublishMessage);
      case PublishCommitSuccess(:final uploadedPaths, :final commitSha):
        // Merge the new file shas into the existing record (preserve the
        // catalogue's entries) and DROP the deleted poster paths (M14) so a
        // later publish does not try to reuse their shas.
        final committed = manifest.afterCommit(
          commitSha: commitSha,
          mergedShas: merge.fileShas,
          coverUrlByBookId: manifest.coverUrlByBookId,
        );
        var localStateSaved = _manifest.save(committed).isRight();

        // F.4 step 7: an accepted commit is not proof that the page is served.
        // Verify the machine-readable section (always present — a publish with
        // zero posters still writes an explicit empty list), then record the
        // truth.
        final verifier = _verifier;
        bool? pagesLive;
        final eventsJson = merge.files
            .where((f) => f.path == EventsSectionBuilder.eventsJsonPath)
            .firstOrNull
            ?.bytes;
        if (verifier != null && eventsJson != null) {
          pagesLive =
              await PublishedFileReadBack(
                verifier: verifier,
                sleep: _sleep,
              ).untilServed(
                siteUrl: target.siteUrl,
                path: EventsSectionBuilder.eventsJsonPath,
                expected: eventsJson,
                revision: now,
              );
          if (pagesLive ?? false) {
            // Manifest `live` FIRST, journal pointer SECOND (R5/E.5). The
            // successful live record supersedes an earlier deployed-save
            // failure; a failed upgrade leaves the journal untouched and is
            // reported instead of being swallowed.
            final liveSaved = _manifest.save(committed.asLive()).isRight();
            localStateSaved = liveSaved;
            if (liveSaved) {
              localStateSaved = (await _hostState.recordVerified(
                target,
              )).isRight();
            }
          }
        }
        return PublishEventsSuccess(
          eventsUrl: eventsUrl,
          uploadedPaths: uploadedPaths,
          localStateSaved: localStateSaved,
          pagesLive: pagesLive,
        );
      case PublishCommitHttpError(:final code):
        // The response body is deliberately dropped: a hostile network can
        // inject arbitrary text into it (§5 "safe message only").
        return PublishEventsFailure(gitHubHttpErrorMessage(code));
    }
  }

  /// Verifies an unconfirmed publication before building on it (F.4 step 2).
  ///
  /// A `matched` result upgrades the record to `live` and lets the journal
  /// claim the address (R33). Both writes are best-effort: the publish
  /// continues either way, and a failed save leaves `deployed`, which is still
  /// the truth.
  Future<PublishVerificationOutcome> _verifyUnconfirmed({
    required PublishManifest local,
    required PublishManifest reconciled,
    required String remoteHead,
    required GitHubPublishTarget target,
    required String siteUrl,
    required int revision,
  }) async {
    final verifier = _verifier;
    if (verifier == null) return PublishVerificationOutcome.notApplicable;
    final outcome =
        await PublishVerificationCheck(verifier: verifier, sleep: _sleep).call(
          localState: local.state,
          localAnchor: local.headSha,
          remoteAnchor: remoteHead,
          expectedSha: reconciled.shaFor(EventsSectionBuilder.eventsJsonPath),
          siteUrl: siteUrl,
          anchorPath: EventsSectionBuilder.eventsJsonPath,
          maxBytes: publishedEventsReadBackMaxBytes,
          revision: revision,
        );
    if (outcome == PublishVerificationOutcome.matched) {
      _manifest.save(reconciled.asLive());
      await _hostState.recordVerified(target);
    }
    return outcome;
  }
}
