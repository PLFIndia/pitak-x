/// Publish-to-GitHub-Pages orchestrator (application layer, AGENTS.md §4, #32).
///
/// Port of Kotlin `PublishLibraryUseCase`. Builds the world-facing bundle
/// (books.json + index.html viewer + salted covers/) and pushes it as ONE
/// atomic, incremental commit via [GitHubApi].
///
/// Pipeline:
///  1. Resolve token + target repo + Pages branch.
///  2. Load (or rebuild) the incremental manifest.
///  3. Redact every non-removed book (F-01) + coarse availability (gated).
///  4. Decide covers: local read / remote fetch, salted paths, sha-diff vs
///     manifest to skip unchanged.
///  5. Build books.json + index.html (name/logo/contact substituted).
///  6. Commit the changed file set; persist the new manifest; poll Pages.
///
/// Cover downscaling (Kotlin `ImagePipeline.downscaleForPublish`) is NOT ported
/// in v1 (Q-P1): covers publish at original size. Correctness is unaffected;
/// only upload size. Flagged as a follow-up.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

/// Coarse publish phases for the UI.
enum PublishPhase {
  /// Building books.json / viewer, deciding what changed.
  preparing,

  /// Creating blobs for changed files.
  uploading,

  /// Tree + commit + ref move.
  committing,

  /// GitHub is building the page (best-effort).
  pagesBuilding,
}

/// Outcome of a publish.
sealed class PublishResult {
  const PublishResult();
}

/// Publish succeeded.
final class PublishSuccess extends PublishResult {
  /// Creates a success result.
  const PublishSuccess({
    required this.pagesUrl,
    required this.uploadedPaths,
    this.availabilityOmitted = false,
    this.pagesLive,
  });

  /// The public page URL.
  final String pagesUrl;

  /// Files whose bytes were uploaded this run.
  final List<String> uploadedPaths;

  /// True when availability was omitted (vault locked at publish).
  final bool availabilityOmitted;

  /// Pages build status: true=live, false=errored, null=unknown.
  final bool? pagesLive;
}

/// Publish failed; [reason] is a safe, human-readable message.
final class PublishFailure extends PublishResult {
  /// Creates a failure result.
  const PublishFailure(this.reason);

  /// Why it failed.
  final String reason;
}

/// Reads a local cover's bytes for [coverUrl], or null when unavailable.
typedef LocalCoverReader = Future<List<int>?> Function(String coverUrl);

/// Fetches a remote cover's bytes from [url], or null on any failure.
typedef RemoteCoverFetcher = Future<List<int>?> Function(String url);

/// Builds the viewer HTML from the bundled template with placeholders filled.
typedef ViewerHtmlBuilderFn = Future<List<int>> Function();

/// Orchestrates a single publish run.
final class PublishLibraryUseCase {
  /// Creates the use case over its ports.
  PublishLibraryUseCase({
    required GitHubApi api,
    required PublishCredentialReader credentials,
    required PublishManifestGateway manifest,
    required PublishCoverIds coverIds,
    required LocalCoverReader readLocalCover,
    required RemoteCoverFetcher fetchRemoteCover,
    required ViewerHtmlBuilderFn buildViewerHtml,
    int Function()? clock,
  }) : _api = api,
       _credentials = credentials,
       _manifest = manifest,
       _coverIds = coverIds,
       _readLocalCover = readLocalCover,
       _fetchRemoteCover = fetchRemoteCover,
       _buildViewerHtml = buildViewerHtml,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final GitHubApi _api;
  final PublishCredentialReader _credentials;
  final PublishManifestGateway _manifest;
  final PublishCoverIds _coverIds;
  final LocalCoverReader _readLocalCover;
  final RemoteCoverFetcher _fetchRemoteCover;
  final ViewerHtmlBuilderFn _buildViewerHtml;
  final int Function() _clock;

  /// Runs the publish. [books] are all library books (removed ones are filtered
  /// here). `activeLoanCounts` is the active-loan count per book id, or null
  /// when the vault is locked (availability then omitted). `encodeBooksJson`
  /// serialises the payload (injected so the JSON encoder stays in one place).
  Future<PublishResult> call({
    required List<Book> books,
    required Map<int, int>? activeLoanCounts,
    required List<int> Function(PublishExport) encodeBooksJson,
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

    final now = _clock();
    final library = books.where((b) => !b.removed).toList();

    final branch =
        await _api.defaultBranch(owner: owner, repo: repo, token: token) ??
        'main';

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

    // Decide covers per book.
    final coverDecisions = <int, _CoverDecision>{};
    for (final book in library) {
      coverDecisions[book.id] = await _decideCover(book, manifest);
    }

    // books.json from redacted books + coarse availability.
    final publishBooks = [
      for (final book in library)
        redactForPublish(
          book,
          availability: _availabilityFor(book, activeLoanCounts),
          resolveCoverUrl: (b) {
            final d = coverDecisions[b.id]!;
            return d.publishedCoverUrl ??
                CoverUrlAllowList.sanitize(b.coverUrl);
          },
        ),
    ];
    final export = PublishExport(exportedAt: now, books: publishBooks);
    final booksJson = encodeBooksJson(export);
    final viewerHtml = await _buildViewerHtml();

    // Assemble the desired file set with per-file change detection.
    final desired = <DesiredFile>[
      _desiredFile('books.json', booksJson, manifest),
      _desiredFile('index.html', viewerHtml, manifest),
    ];
    for (final d in coverDecisions.values) {
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
            },
          ),
        );
        phase(PublishPhase.pagesBuilding);
        bool? pagesLive;
        try {
          pagesLive = await _api.latestPagesBuildStatus(
            owner: owner,
            repo: repo,
            token: token,
          );
        } on GitHubApiException {
          pagesLive = null;
        }
        return PublishSuccess(
          pagesUrl: 'https://$owner.github.io/$repo/',
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

  String? _availabilityFor(Book book, Map<int, int>? counts) {
    if (counts == null) return null;
    final active = counts[book.id] ?? 0;
    return active >= book.copyCount ? PublishBook.out : PublishBook.available;
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

  Future<_CoverDecision> _decideCover(
    Book book,
    PublishManifest manifest,
  ) async {
    final src = book.coverUrl?.trim() ?? '';
    if (src.isEmpty) return const _CoverDecision();
    final publishPath = await _coverIds.pathFor(book.id);
    final repoSha = manifest.shaFor(publishPath);

    // LOCAL cover: read bytes, sha them (detects user edits).
    if (_isLocal(src)) {
      final bytes = await _readLocalCover(src);
      if (bytes != null) {
        return _CoverDecision(
          publishPath: publishPath,
          bytes: bytes,
          gitSha: GitBlobSha.of(bytes),
          publishedCoverUrl: publishPath,
        );
      }
      if (repoSha != null) {
        return _CoverDecision(
          publishPath: publishPath,
          reuseSha: repoSha,
          publishedCoverUrl: publishPath,
        );
      }
      return const _CoverDecision();
    }

    // REMOTE cover: source-identity skip when URL unchanged + already in repo.
    final urlUnchanged = manifest.coverUrlByBookId['${book.id}'] == src;
    if (urlUnchanged && repoSha != null) {
      return _CoverDecision(
        publishPath: publishPath,
        reuseSha: repoSha,
        publishedCoverUrl: publishPath,
      );
    }
    final bytes = await _fetchRemoteCover(src);
    if (bytes != null) {
      return _CoverDecision(
        publishPath: publishPath,
        bytes: bytes,
        gitSha: GitBlobSha.of(bytes),
        publishedCoverUrl: publishPath,
      );
    }
    if (repoSha != null) {
      return _CoverDecision(
        publishPath: publishPath,
        reuseSha: repoSha,
        publishedCoverUrl: publishPath,
      );
    }
    // No usable cover bytes: fall back to a sanitized remote URL or drop.
    return _CoverDecision(publishedCoverUrl: CoverUrlAllowList.sanitize(src));
  }

  static bool _isLocal(String s) =>
      s.startsWith('covers/') || s.startsWith('file://');
}

/// Per-book cover decision (internal).
final class _CoverDecision {
  const _CoverDecision({
    this.publishPath,
    this.bytes,
    this.gitSha,
    this.reuseSha,
    this.publishedCoverUrl,
  });

  final String? publishPath;
  final List<int>? bytes;
  final String? gitSha;
  final String? reuseSha;
  final String? publishedCoverUrl;
}

/// Load/save view of the manifest the orchestrator needs.
abstract interface class PublishManifestGateway {
  /// Loads the manifest (or empty).
  PublishManifest load();

  /// Persists [manifest].
  void save(PublishManifest manifest);
}
