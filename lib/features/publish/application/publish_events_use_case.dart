/// Publish-events orchestrator (application layer, AGENTS.md §4, #events).
///
/// A SELF-CONTAINED publish path for the events page, independent of the
/// catalogue publish (Q5=A): the library can update/clear its posters without
/// re-publishing the book list, and vice versa. It pushes `events.html`, the
/// machine-readable `events.json`, and the poster images as ONE atomic
/// incremental commit via [GitHubGitDataApi] (the git-data role of the GitHub
/// port, S5), reusing the same credential + target repo a prior catalogue
/// publish established.
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
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_events_ports.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
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
  });

  /// Public URL of the events page.
  final String eventsUrl;

  /// Files whose bytes were uploaded this run.
  final List<String> uploadedPaths;
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
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PosterBytesReader readPoster,
    required EventsHtmlBuilderFn buildEventsHtml,
    required EventsJsonFactory buildEventsJson,
    int Function()? clock,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _section = EventsSectionBuilder(
         readPoster: readPoster,
         buildEventsHtml: buildEventsHtml,
         buildEventsJson: buildEventsJson,
       ),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubGitDataApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final EventsSectionBuilder _section;
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
    final ownerRepo = await _credentials.targetRepo();
    final parts = ownerRepo?.split('/');
    if (ownerRepo == null || parts == null || parts.length != 2) {
      return const PublishEventsFailure('Pick a target repo first.');
    }
    final owner = parts[0];
    final repo = parts[1];
    // N09: ONE resolver for every published address (user site vs project
    // site) — shared with the catalogue publish and the drawer.
    final eventsUrl = githubPagesFileUrl(ownerRepo, 'events.html');
    if (eventsUrl == null) {
      return const PublishEventsFailure('Pick a target repo first.');
    }

    // Gate (Q8=A): the catalogue must have been published to THIS repo.
    final manifest = _manifest.load();
    if (manifest.repo != ownerRepo ||
        manifest.shaFor(_catalogueMarker) == null) {
      return const PublishEventsFailure(
        'Publish your catalogue first, then publish events.',
      );
    }

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

    // Build the section with the SHARED builder: one filtered poster list
    // feeds HTML, JSON and the uploads, so unreadable posters can never
    // appear in one representation but not another.
    final built = await _section.build(
      content: content,
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
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const PublishEventsFailure(gitHubNetworkErrorMessage);
    }

    switch (result) {
      case PublishCommitSuccess(:final uploadedPaths):
        // Merge the new file shas into the existing record (preserve the
        // catalogue's entries) and DROP the deleted poster paths (M14) so a
        // later publish does not try to reuse their shas.
        _manifest.save(
          PublishManifest(
            repo: ownerRepo,
            fileShas: merge.fileShas,
            coverUrlByBookId: manifest.coverUrlByBookId,
          ),
        );
        return PublishEventsSuccess(
          eventsUrl: eventsUrl,
          uploadedPaths: uploadedPaths,
        );
      case PublishCommitHttpError(:final code):
        // The response body is deliberately dropped: a hostile network can
        // inject arbitrary text into it (§5 "safe message only").
        return PublishEventsFailure(gitHubHttpErrorMessage(code));
    }
  }
}
