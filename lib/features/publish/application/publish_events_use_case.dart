/// Publish-events orchestrator (application layer, AGENTS.md §4, #events).
///
/// A SELF-CONTAINED publish path for the events page, independent of the
/// catalogue publish (Q5=A): the library can update/clear its posters without
/// re-publishing the book list, and vice versa. It pushes only `events.html` +
/// the poster images as ONE atomic incremental commit via [GitHubApi], reusing
/// the same credential + target repo a prior catalogue publish established.
///
/// Gate (Q8=A): refuses unless the on-device publish manifest proves the
/// catalogue was already published to the CURRENT target repo (it contains an
/// `index.html` entry for that repo). This keeps "the website exists" true
/// before we add a second page to it.
///
/// Posters are tiny (max 2), so there is no incremental cover-style diffing:
/// every published file's bytes are git-sha'd and only uploaded when changed
/// vs the manifest — cheap and correct.
library;

import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';

/// Reads a poster image's bytes for its relative ref, or null when missing.
typedef PosterBytesReader = Future<List<int>?> Function(String imageRef);

/// Builds the events page HTML for the given published posters.
typedef EventsHtmlBuilderFn =
    Future<List<int>> Function(List<PublishPoster> posters);

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
    required GitHubApi api,
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PosterBytesReader readPoster,
    required EventsHtmlBuilderFn buildEventsHtml,
    int Function()? clock,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _readPoster = readPoster,
       _buildEventsHtml = buildEventsHtml,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final PosterBytesReader _readPoster;
  final EventsHtmlBuilderFn _buildEventsHtml;
  final int Function() _clock;

  /// Repo path of the catalogue page whose presence proves "already published".
  static const String _catalogueMarker = 'index.html';

  /// Runs the events publish for [content].
  Future<PublishEventsResult> call(EventsContent content) async {
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

    // Gate (Q8=A): the catalogue must have been published to THIS repo.
    final manifest = _manifest.load();
    if (manifest.repo != ownerRepo ||
        manifest.shaFor(_catalogueMarker) == null) {
      return const PublishEventsFailure(
        'Publish your catalogue first, then publish events.',
      );
    }

    final branch =
        await _api.defaultBranch(owner: owner, repo: repo, token: token) ??
        'main';

    // Resolve poster bytes + their published repo paths. A poster whose local
    // image is missing is dropped (never publishes a broken <img>).
    final published = <PublishPoster>[];
    final posterFiles = <DesiredFile>[];
    for (final poster in content.posters) {
      final bytes = await _readPoster(poster.imageRef);
      if (bytes == null) continue;
      final path = poster.imageRef; // already `posters/<id>.jpg`
      final sha = GitBlobSha.of(bytes);
      posterFiles.add(
        DesiredFile(
          path: path,
          bytes: bytes,
          gitSha: sha,
          upload: manifest.shaFor(path) != sha,
        ),
      );
      published.add(
        PublishPoster(imagePath: path, description: poster.description),
      );
    }

    final eventsHtml = await _buildEventsHtml(published);
    final htmlSha = GitBlobSha.of(eventsHtml);
    final files = <DesiredFile>[
      DesiredFile(
        path: 'events.html',
        bytes: eventsHtml,
        gitSha: htmlSha,
        upload: manifest.shaFor('events.html') != htmlSha,
      ),
      ...posterFiles,
    ];

    final now = _clock();
    final PublishCommitResult result;
    try {
      result = await _api.commitFiles(
        owner: owner,
        repo: repo,
        branch: branch,
        token: token,
        files: files,
        commitMessage: 'Pitak events publish $now',
      );
    } on GitHubApiException catch (e) {
      return PublishEventsFailure('Network error: ${e.message}');
    }

    switch (result) {
      case PublishCommitSuccess(:final uploadedPaths):
        // Merge the new file shas into the existing manifest (preserve the
        // catalogue's entries so a later catalogue publish still diffs right).
        _manifest.save(
          PublishManifest(
            repo: ownerRepo,
            fileShas: {
              ...manifest.fileShas,
              for (final f in files) f.path: f.gitSha,
            },
            coverUrlByBookId: manifest.coverUrlByBookId,
          ),
        );
        return PublishEventsSuccess(
          eventsUrl: 'https://$owner.github.io/$repo/events.html',
          uploadedPaths: uploadedPaths,
        );
      case PublishCommitHttpError(:final code, :final body):
        final excerpt = body.substring(0, body.length.clamp(0, 200));
        return PublishEventsFailure('GitHub HTTP $code: $excerpt');
    }
  }
}
