/// Cover publish decisions (application layer, AGENTS.md §4, #32).
///
/// Extracted from `PublishLibraryUseCase` when ADR 0014 W4 added periodical
/// covers to the same pipeline (the use case file would otherwise cross the
/// 500-line cap, B.5). ONE implementation decides every cover — book or
/// series — so the local/remote/reuse rules can never drift between kinds.
///
/// The decision for one cover source:
///  - LOCAL cover (`covers/…` / `file://`): bytes are read and sha-d (an
///    edit changes the sha, so it re-uploads); unreadable bytes fall back to
///    the already-published file when the repo has one.
///  - REMOTE cover: skipped when the URL is unchanged since the last
///    publish AND the repo already has the file (source-identity skip via
///    the manifest's `coverUrlByBookId`); otherwise fetched (bounded,
///    allow-listed hosts — M09). A failed fetch likewise reuses the
///    published file, else degrades to the sanitized remote URL.
///  - No usable bytes anywhere: the allow-listed URL or null (cover dropped).
library;

import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';

/// Reads a local cover's bytes for [coverUrl], or null when unavailable.
typedef LocalCoverReader = Future<List<int>?> Function(String coverUrl);

/// Fetches a remote cover's bytes from [url], or null on any failure.
typedef RemoteCoverFetcher = Future<List<int>?> Function(String url);

/// The decided fate of one cover (internal to the publish flow).
final class CoverDecision {
  /// Creates a decision; every field null means "no cover to publish".
  const CoverDecision({
    this.publishPath,
    this.bytes,
    this.gitSha,
    this.reuseSha,
    this.publishedCoverUrl,
  });

  /// Repo-relative salted path (`covers/<hash>.jpg`) this cover publishes as.
  final String? publishPath;

  /// Bytes to upload (null when reusing the already-published file).
  final List<int>? bytes;

  /// Git blob sha of [bytes] (the manifest diff key).
  final String? gitSha;

  /// Blob sha of the file ALREADY in the repo, reused without an upload.
  final String? reuseSha;

  /// The URL the payload entry points at (the salted path, or a sanitized
  /// remote URL when no bytes were usable).
  final String? publishedCoverUrl;
}

/// Decides covers for one publish run.
final class PublishCoverDecider {
  /// Creates the decider over its ports.
  const PublishCoverDecider({
    required PublishCoverIds coverIds,
    required LocalCoverReader readLocalCover,
    required RemoteCoverFetcher fetchRemoteCover,
  }) : _coverIds = coverIds,
       _readLocalCover = readLocalCover,
       _fetchRemoteCover = fetchRemoteCover;

  final PublishCoverIds _coverIds;
  final LocalCoverReader _readLocalCover;
  final RemoteCoverFetcher _fetchRemoteCover;

  /// Decides the cover of one item: [coverUrl] is the source reference,
  /// [itemId] the identity the salted path is hashed from.
  ///
  /// Beginner note: the salted path hides the per-device id in the public
  /// repo (see `PublishCoverIds`); the manifest's sha/source-identity skips
  /// are what make a re-publish of an unchanged cover upload nothing.
  Future<CoverDecision> forItem(
    String? coverUrl, {
    required int itemId,
    required PublishManifest manifest,
  }) => _decide(
    coverUrl,
    manifest,
    publishPath: () => _coverIds.pathFor(itemId),
    urlKey: '$itemId',
  );

  /// Decides the cover of one periodical, keyed on its stable uid (ADR 0014
  /// W4) — one series cover is ONE upload, referenced by the series entry
  /// and by every issue that falls back to it (`IssueCover.resolve`).
  Future<CoverDecision> forPeriodical(
    String? coverUrl, {
    required String periodicalUid,
    required PublishManifest manifest,
  }) => _decide(
    coverUrl,
    manifest,
    publishPath: () => _coverIds.pathForPeriodical(periodicalUid),
    urlKey: 'periodical:$periodicalUid',
  );

  Future<CoverDecision> _decide(
    String? coverUrl,
    PublishManifest manifest, {
    required Future<String> Function() publishPath,
    required String urlKey,
  }) async {
    final src = coverUrl?.trim() ?? '';
    if (src.isEmpty) return const CoverDecision();
    final path = await publishPath();
    final repoSha = manifest.shaFor(path);

    // LOCAL cover: read bytes, sha them (detects user edits).
    if (_isLocal(src)) {
      final bytes = await _readLocalCover(src);
      if (bytes != null) {
        return CoverDecision(
          publishPath: path,
          bytes: bytes,
          gitSha: GitBlobSha.of(bytes),
          publishedCoverUrl: path,
        );
      }
      if (repoSha != null) {
        return CoverDecision(
          publishPath: path,
          reuseSha: repoSha,
          publishedCoverUrl: path,
        );
      }
      return const CoverDecision();
    }

    // REMOTE cover: source-identity skip when URL unchanged + already in repo.
    final urlUnchanged = manifest.coverUrlByBookId[urlKey] == src;
    if (urlUnchanged && repoSha != null) {
      return CoverDecision(
        publishPath: path,
        reuseSha: repoSha,
        publishedCoverUrl: path,
      );
    }
    final bytes = await _fetchRemoteCover(src);
    if (bytes != null) {
      return CoverDecision(
        publishPath: path,
        bytes: bytes,
        gitSha: GitBlobSha.of(bytes),
        publishedCoverUrl: path,
      );
    }
    if (repoSha != null) {
      return CoverDecision(
        publishPath: path,
        reuseSha: repoSha,
        publishedCoverUrl: path,
      );
    }
    // No usable cover bytes: fall back to a sanitized remote URL or drop.
    return CoverDecision(publishedCoverUrl: CoverUrlAllowList.sanitize(src));
  }

  static bool _isLocal(String s) =>
      s.startsWith('covers/') || s.startsWith('file://');
}
