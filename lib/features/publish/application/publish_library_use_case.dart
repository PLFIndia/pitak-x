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
///  3. Redact every non-removed item (F-01) + coarse availability (gated),
///     and every non-removed series (ADR 0014 W3 — `periodicals[]`).
///  4. Decide covers (`PublishCoverDecider`): local read / remote fetch,
///     salted paths, sha-diff vs manifest to skip unchanged. A series cover
///     is decided ONCE and shared by its entry and every issue that falls
///     back to it (W4's `IssueCover.resolve` rule, applied at publish).
///  5. Build books.json + index.html (name/logo/contact substituted).
///  6. Commit the changed file set; persist the new manifest; poll Pages.
///
/// Cover downscaling (Kotlin `ImagePipeline.downscaleForPublish`) is NOT ported
/// in v1 (Q-P1): covers publish at original size. Correctness is unaffected;
/// only upload size. Flagged as a follow-up.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_cover.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/github_pages_url.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_periodical_links.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

// The cover-IO typedefs live with the decider since S20 (plan magazines);
// re-exported so existing imports of this file keep resolving (one import
// per caller, the S19 idiom). Publish results follow the same compatibility
// rule after their S8 extraction kept this orchestrator below 500 lines.
export 'publish_cover_decider.dart' show LocalCoverReader, RemoteCoverFetcher;
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

/// Builds the viewer HTML from the bundled template with placeholders filled.
typedef ViewerHtmlBuilderFn = Future<List<int>> Function();

/// Fetches a PUBLIC published file's bytes from [url] (no auth), or null on
/// any failure. Used for the post-publish read-back only.
typedef PublishedFileFetcher = Future<List<int>?> Function(String url);

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
    PublishedFileFetcher? fetchPublishedFile,
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
       _fetchPublishedFile = fetchPublishedFile,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubGitDataApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final PublishCoverDecider _covers;
  final ViewerHtmlBuilderFn _buildViewerHtml;

  /// Null ⇒ read-back skipped (tests / no network port wired).
  final PublishedFileFetcher? _fetchPublishedFile;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  /// Read-back budget: [readBackAttempts] polls, [readBackInterval] apart
  /// (Orange budgets 120 s; 60 s covers typical Pages builds and keeps the
  /// worst-case wait tolerable on a phone). ALWAYS terminates.
  static const int readBackAttempts = 12;

  /// Pause between read-back polls.
  static const Duration readBackInterval = Duration(seconds: 5);

  /// Repo-relative path of the network descriptor (docs/ARCHITECTURE.md §5.1). One
  /// constant so the write, the sha-diff skip and the delete path agree.
  static const String libraryJsonPath = 'library.json';

  /// Runs the publish. [books] are all library items of any kind (removed
  /// ones are filtered here). [periodicals] are all magazine titles
  /// (ADR 0014 W3): the non-removed ones publish as `periodicals[]`; a
  /// removed series gets no entry, but its issues are still live library
  /// rows (D8) and publish with the series-cover fallback.
  /// `activeLoanCounts` is the active-loan count per item id, or null
  /// when the vault is locked (availability then omitted). `encodeBooksJson`
  /// serialises the payload (injected so the JSON encoder stays in one place).
  ///
  /// [libraryJson] is the pre-encoded `library.json` network descriptor
  /// (docs/ARCHITECTURE.md §5.1), or null when none may be written — null REMOVES a
  /// previously published descriptor in the same commit (M14 `deletePaths`),
  /// so a stale location never outlives the user's opt-out.
  Future<PublishResult> call({
    required List<CatalogueItem> books,
    required List<Periodical> periodicals,
    required Map<int, int>? activeLoanCounts,
    required List<int> Function(PublishExport) encodeBooksJson,
    required List<int>? libraryJson,
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
    final library = books.where((b) => !b.removed).toList();

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

    final availabilityOmitted = activeLoanCounts == null;

    // Resolve every link before cover IO or artifact construction. A malformed
    // persisted identity must never become an ungrouped/partially covered file.
    final periodicalByUid = PublishPeriodicalLinks.resolve(
      books: library,
      periodicals: periodicals,
    );
    if (periodicalByUid == null) {
      return const PublishFailure(
        'Some magazine series or issue links are invalid. '
        'Nothing was published.',
      );
    }
    // Removed series stay in periodicalByUid for issue cover fallback (D8),
    // but only live series publish a top-level entry.
    final publishedPeriodicals = periodicals.where((p) => !p.removed).toList();

    // Decide covers. A series cover is decided ONCE per publish and shared
    // by the series entry and every issue that falls back to it — the W4
    // rule (`IssueCover.resolve`) decides WHICH source an entry shows, the
    // decider decides where that source's bytes live in the repo.
    final coverDecisions = <int, CoverDecision>{};
    final periodicalCoverDecisions = <String, CoverDecision>{};
    Future<CoverDecision> decidePeriodicalCover(Periodical series) async {
      final uid = series.periodicalUid!;
      final cached = periodicalCoverDecisions[uid];
      if (cached != null) return cached;
      final decision = await _covers.forPeriodical(
        series.coverUrl,
        periodicalUid: uid,
        manifest: manifest,
      );
      return periodicalCoverDecisions[uid] = decision;
    }

    for (final book in library) {
      final series = periodicalByUid[book.issue?.periodicalUid];
      final resolved = IssueCover.resolve(book, series);
      if (resolved == null) continue;
      if (_isOwnCover(book, resolved)) {
        coverDecisions[book.id] = await _covers.forItem(
          book.coverUrl,
          itemId: book.id,
          manifest: manifest,
        );
      } else if (series != null) {
        await decidePeriodicalCover(series);
      }
    }
    // A published series with a cover of its own gets its decision even
    // when no issue falls back to it (the series entry shows it).
    for (final series in publishedPeriodicals) {
      if ((series.coverUrl?.trim() ?? '').isNotEmpty) {
        await decidePeriodicalCover(series);
      }
    }

    // books.json from redacted items + series + coarse availability.
    final publishBooks = [
      for (final book in library)
        redactForPublish(
          book,
          availability: _availabilityFor(book, activeLoanCounts),
          resolveCoverUrl: (b) {
            final series = periodicalByUid[b.issue?.periodicalUid];
            final resolved = IssueCover.resolve(b, series);
            if (resolved == null) return null;
            if (_isOwnCover(b, resolved)) {
              return coverDecisions[b.id]?.publishedCoverUrl ??
                  CoverUrlAllowList.sanitize(resolved);
            }
            return periodicalCoverDecisions[series!.periodicalUid]
                    ?.publishedCoverUrl ??
                CoverUrlAllowList.sanitize(resolved);
          },
        ),
    ];
    final export = PublishExport(
      exportedAt: now,
      books: publishBooks,
      periodicals: [
        for (final series in publishedPeriodicals)
          redactPeriodicalForPublish(
            series,
            resolveCoverUrl: (p) =>
                periodicalCoverDecisions[p.periodicalUid]?.publishedCoverUrl ??
                CoverUrlAllowList.sanitize(p.coverUrl),
          ),
      ],
    );
    final booksJson = encodeBooksJson(export);
    final viewerHtml = await _buildViewerHtml();

    // Assemble the desired file set with per-file change detection.
    final desired = <DesiredFile>[
      _desiredFile('books.json', booksJson, manifest),
      // The network descriptor rides in the SAME atomic commit (docs/ARCHITECTURE.md
      // §5.1): books.json, library.json and index.html always agree on the
      // live site. Incremental publish skips it when the bytes are unchanged
      // (the codec's stable key order makes equal input ⇒ equal blob sha).
      if (libraryJson != null)
        _desiredFile(libraryJsonPath, libraryJson, manifest),
      _desiredFile('index.html', viewerHtml, manifest),
    ];
    for (final d in [
      ...coverDecisions.values,
      ...periodicalCoverDecisions.values,
    ]) {
      if (d.bytes != null && d.publishPath != null && d.gitSha != null) {
        desired.add(
          DesiredFile(
            path: d.publishPath!,
            bytes: d.bytes!,
            gitSha: d.gitSha!,
            upload: manifest.shaFor(d.publishPath!) != d.gitSha,
          ),
        );
      } else if (d.reuseSha != null && d.publishPath != null) {
        desired.add(
          DesiredFile(
            path: d.publishPath!,
            bytes: const [],
            gitSha: d.reuseSha!,
            upload: false,
          ),
        );
      }
    }
    // De-dup by path (deterministic: keep the first).
    final seen = <String>{};
    final deduped = [
      for (final f in desired)
        if (seen.add(f.path)) f,
    ];

    phase(
      deduped.any((f) => f.upload)
          ? PublishPhase.uploading
          : PublishPhase.committing,
    );

    final PublishCommitResult result;
    try {
      result = await _api.commitFiles(
        owner: owner,
        repo: repo,
        branch: branch,
        token: token,
        files: deduped,
        commitMessage: 'Pitaka publish $now',
        // Opt-out path (docs/ARCHITECTURE.md §5.1): with no descriptor to write, a
        // library.json published by an EARLIER run is deleted in this same
        // commit — GitHub's create-tree drops entries whose sha is null
        // (M14). Only app-owned paths, only when they exist in the repo.
        deletePaths:
            libraryJson == null && manifest.shaFor(libraryJsonPath) != null
            ? const [libraryJsonPath]
            : const [],
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
            fileShas: {for (final f in deduped) f.path: f.gitSha},
            coverUrlByBookId: {
              for (final b in library)
                if (b.coverUrl != null && b.coverUrl!.isNotEmpty)
                  '${b.id}': b.coverUrl!,
              // Series covers ride under the decider's 'periodical:' urlKey
              // so the remote source-identity skip works for them without
              // sharing the book id key space. Stored TRIMMED to match the
              // trimmed value the decider compares against.
              for (final p in periodicalByUid.values)
                if ((p.coverUrl?.trim() ?? '').isNotEmpty)
                  'periodical:${p.periodicalUid}': p.coverUrl!.trim(),
            },
          ),
        );
        phase(PublishPhase.pagesBuilding);
        // `pagesUrl` came from the single resolver (github_pages_url.dart),
        // shared with the events publish and the drawer's share action.
        // Read-back verification (à la Localcart Orange github_pages.rs §6):
        // poll the LIVE books.json with a cache-buster until it serves
        // exactly the bytes we just published. Bounded — it can never spin
        // forever — and "live" means the real site, not a build-status API.
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

  /// Polls the live site (bounded) until books.json serves [expected].
  /// Returns true when verified, null when the budget ran out or no fetch
  /// port is wired. Never throws, never loops unbounded.
  Future<bool?> _verifyLive(
    String pagesUrl,
    List<int> expected,
    int revision,
  ) async {
    final fetch = _fetchPublishedFile;
    if (fetch == null) return null;
    for (var attempt = 0; attempt < readBackAttempts; attempt++) {
      await _sleep(readBackInterval);
      // Cache-buster per attempt so a CDN can't serve a stale copy.
      final body = await fetch('${pagesUrl}books.json?rb=$revision-$attempt');
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

  String? _availabilityFor(CatalogueItem book, Map<int, int>? counts) {
    if (counts == null) return null;
    final active = counts[book.id] ?? 0;
    return active >= book.copyCount ? PublishItem.out : PublishItem.available;
  }

  DesiredFile _desiredFile(
    String path,
    List<int> bytes,
    PublishManifest manifest,
  ) {
    final sha = GitBlobSha.of(bytes);
    return DesiredFile(
      path: path,
      bytes: bytes,
      gitSha: sha,
      upload: manifest.shaFor(path) != sha,
    );
  }

  /// True when [resolved] (the output of `IssueCover.resolve`) is [book]'s
  /// OWN cover rather than its series' — resolve()'s rule is "non-blank own
  /// cover, else the series cover", so the same branch decides whose salted
  /// path (item id vs `periodical:` uid) owns the upload.
  static bool _isOwnCover(CatalogueItem book, String resolved) {
    final own = book.coverUrl?.trim() ?? '';
    return own.isNotEmpty && own == resolved;
  }
}

/// Load/save view of the manifest the orchestrator needs.
abstract interface class PublishManifestGateway {
  /// Loads the manifest (or empty).
  PublishManifest load();

  /// Persists [manifest].
  void save(PublishManifest manifest);
}
