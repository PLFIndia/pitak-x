/// Publish-to-GitHub-Pages orchestrator (application layer, AGENTS.md §4, #32).
///
/// Port of Kotlin `PublishLibraryUseCase`. Builds the world-facing bundle
/// (books.json + index.html viewer + salted covers/) and pushes it as ONE
/// atomic, incremental commit via [GitHubGitDataApi] (the git-data role of
/// the GitHub port, S5 — this use case never touches auth or repo admin).
///
/// Pipeline:
///  1. Resolve token + target repo + the branch Pages SERVES from (N09: read
///     live from the Pages configuration, never assumed to be the default
///     branch; Pages off or re-pointed → typed failure before any write).
///  2. Load (or rebuild) the incremental manifest.
///  3. Build the catalogue section with the SHARED builder (Cloudflare plan
///     R3) — the same code the Cloudflare adapter consumes, so the two hosts
///     cannot drift.
///  4. Merge that section into the publication record (R7): only its own
///     paths are replaced, the events section survives.
///  5. Commit the changed file set + exact owned deletions; persist the merged
///     manifest; read the live site back (bounded).
///
/// Cover images are downscaled by the injected local-cover reader
/// (`ImageDownscaler`, 400×600 q80 — the single image choke point), so a
/// publish uploads small JPEGs and EXIF/GPS never leaves the device.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

// The cover-IO typedefs live with the decider since S20 (plan magazines);
// re-exported so existing imports of this file keep resolving (one import
// per caller, the S19 idiom). Publish results follow the same compatibility
// rule after their S8 extraction kept this orchestrator below 500 lines.
export 'publish_cover_decider.dart' show LocalCoverReader, RemoteCoverFetcher;
export 'publish_result.dart';
export 'site/catalogue_section_builder.dart' show ViewerHtmlBuilderFn;

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
    required PublishCoverIds coverIds,
    required LocalCoverReader readLocalCover,
    required RemoteCoverFetcher fetchRemoteCover,
    required ViewerHtmlBuilderFn buildViewerHtml,
    PublishedSiteVerifier? verifier,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _covers = PublishCoverDecider(
         coverIds: coverIds,
         readLocalCover: readLocalCover,
         fetchRemoteCover: fetchRemoteCover,
       ),
       _buildViewerHtml = buildViewerHtml,
       _verifier = verifier,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubGitDataApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final PublishCoverDecider _covers;
  final ViewerHtmlBuilderFn _buildViewerHtml;

  /// Null ⇒ read-back skipped (tests / no network port wired).
  final PublishedSiteVerifier? _verifier;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  /// Read-back budget: [readBackAttempts] polls, [readBackInterval] apart
  /// (Orange budgets 120 s; 60 s covers typical Pages builds and keeps the
  /// worst-case wait tolerable on a phone). ALWAYS terminates.
  static const int readBackAttempts = 12;

  /// Pause between read-back polls.
  static const Duration readBackInterval = Duration(seconds: 5);

  /// Repo-relative path of the network descriptor (docs/ARCHITECTURE.md §5.1).
  static const String libraryJsonPath = CatalogueSectionBuilder.libraryJsonPath;

  /// Runs the publish. [books] are all library items of any kind (removed
  /// ones are filtered here). [periodicals] are all magazine titles
  /// (ADR 0014 W3): the non-removed ones publish as `periodicals[]`; a
  /// removed series gets no entry, but its issues are still live library
  /// rows (D8) and publish with the series-cover fallback.
  /// [activeLoanCounts] is the active-loan count per item id, or null
  /// when the vault is locked (availability then omitted).
  ///
  /// [libraryJson] is the pre-encoded `library.json` network descriptor, or
  /// null when none may be written — null REMOVES a previously published
  /// descriptor in the same commit (M14), so a stale location never outlives
  /// the user's opt-out.
  ///
  /// [mode] is [PublishMode.complete] for a move or a whole-site
  /// replacement: every required cover must then resolve to usable bytes, and
  /// a missing one fails typed BEFORE any write.
  Future<PublishResult> call({
    required List<CatalogueItem> books,
    required List<Periodical> periodicals,
    required Map<int, int>? activeLoanCounts,
    required List<int> Function(PublishExport) encodeBooksJson,
    required List<int>? libraryJson,
    PublishMode mode = PublishMode.incremental,
    void Function(PublishPhase)? onPhase,
  }) async {
    void phase(PublishPhase p) => onPhase?.call(p);
    phase(PublishPhase.preparing);

    final token = await _credentials.token();
    if (token == null) return const PublishFailure('Not signed in to GitHub.');
    final ownerRepo = await _credentials.targetRepo();
    final parts = ownerRepo?.split('/');
    if (ownerRepo == null || parts == null || parts.length != 2) {
      return const PublishFailure('Pick a target repo first.');
    }
    final owner = parts[0];
    final repo = parts[1];
    // The address is derived by the shared resolver (user site vs project
    // site); a target that cannot be resolved is refused before any write.
    final pagesUrl = githubPagesUrlFor(ownerRepo);
    if (pagesUrl == null) {
      return const PublishFailure('Pick a target repo first.');
    }

    final now = _clock();
    final availabilityOmitted = activeLoanCounts == null;

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

    // Load manifest; rebuild from the repo tree if missing / for another repo.
    var manifest = _manifest.load();
    if (manifest.repo != ownerRepo || manifest.fileShas.isEmpty) {
      try {
        final shas = await _api.headTreeShas(
          owner: owner,
          repo: repo,
          branch: branch,
          token: token,
        );
        manifest = PublishManifest(repo: ownerRepo, fileShas: shas);
      } on GitHubApiException {
        manifest = PublishManifest(repo: ownerRepo);
      }
    }

    // Build the section with the shared builder (the same bytes every host
    // publishes). A typed failure here means NOTHING was written.
    final built =
        await CatalogueSectionBuilder(
          covers: _covers,
          buildViewerHtml: _buildViewerHtml,
          encodeBooksJson: encodeBooksJson,
        ).build(
          books: books,
          periodicals: periodicals,
          activeLoanCounts: activeLoanCounts,
          libraryJson: libraryJson,
          previous: manifest,
          now: now,
          mode: mode,
        );
    final section = built.fold((failure) => null, (value) => value);
    if (section == null) {
      return PublishFailure(_messageFor(built.swap().toNullable()!));
    }

    // R7: merge ONLY this section into the publication record. The events
    // section (and any other app-owned path) survives; the section's own
    // dropped paths become exact deletions (never a prefix sweep).
    final merge = mergeSection(previous: manifest, section: section);

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
      );
    } on GitHubApiException {
      // Fixed message (§5): exception text can embed URLs/response detail.
      return const PublishFailure(gitHubNetworkErrorMessage);
    }

    switch (result) {
      case PublishCommitSuccess(:final uploadedPaths):
        _manifest.save(
          PublishManifest(
            repo: ownerRepo,
            fileShas: merge.fileShas,
            coverUrlByBookId: section.coverUrlByKey,
          ),
        );
        phase(PublishPhase.pagesBuilding);
        // `pagesUrl` came from the single resolver (github_pages_url.dart),
        // shared with the events publish and the drawer's share action.
        // Bounded read-back: poll the LIVE books.json with a cache-buster
        // until it serves exactly the bytes just published.
        final booksJson = merge.files
            .firstWhere((f) => f.path == CatalogueSectionBuilder.booksJsonPath)
            .bytes;
        final pagesLive = await _verifyLive(pagesUrl, booksJson, now);
        return PublishSuccess(
          pagesUrl: pagesUrl,
          uploadedPaths: uploadedPaths,
          availabilityOmitted: availabilityOmitted,
          pagesLive: pagesLive,
        );
      case PublishCommitHttpError(:final code):
        // The response body is deliberately dropped: a hostile network can
        // inject arbitrary text into it (§5 "safe message only").
        return PublishFailure(gitHubHttpErrorMessage(code));
    }
  }

  /// Maps a typed failure to the fixed, user-facing publish message.
  static String _messageFor(Failure failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    _ => 'Something went wrong. Nothing was published.',
  };

  /// Polls the live site (bounded) until books.json serves [expected].
  /// Returns true when verified, null when the budget ran out or no fetch
  /// port is wired. Never throws, never loops unbounded.
  Future<bool?> _verifyLive(
    String pagesUrl,
    List<int> expected,
    int revision,
  ) async {
    final verifier = _verifier;
    if (verifier == null) return null;
    for (var attempt = 0; attempt < readBackAttempts; attempt++) {
      await _sleep(readBackInterval);
      // Origin-bound, redirect-free, capped at exactly the expected size (a
      // longer body cannot be the file we wrote). A fresh cache-buster per
      // attempt so a CDN cannot answer with a stale copy.
      final body = await verifier.read(
        siteUrl: pagesUrl,
        path: 'books.json',
        maxBytes: expected.isEmpty ? 1 : expected.length,
        cacheBuster: '$revision-$attempt',
      );
      if (body != null && _sameBytes(body, expected)) return true;
    }
    return null;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Load/save view of the manifest the orchestrator needs.
abstract interface class PublishManifestGateway {
  /// Loads the manifest (or empty).
  PublishManifest load();

  /// Persists [manifest].
  void save(PublishManifest manifest);
}
