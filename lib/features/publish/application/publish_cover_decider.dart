/// Cover publish decisions (application layer, AGENTS.md §4, #32).
///
/// Extracted from `PublishLibraryUseCase` when ADR 0014 W4 added periodical
/// covers to the same pipeline (the use case file would otherwise cross the
/// 500-line cap, B.5). ONE implementation decides every cover — book or
/// series — so the local/remote/reuse rules can never drift between kinds.
///
/// The decision for one cover source, in this order:
///  1. REUSE, unread (ADR 0020, plan CV2): an incremental publish whose
///     record holds this cover's path, names the SAME source for its key and
///     was made with the current rendition (`PublishCoverRendition`) reuses
///     the published file without reading or re-encoding anything. Before
///     ADR 0020 only remote covers skipped (by URL alone); every local cover
///     was re-read and re-encoded on every publish, which cost about 4 min 46 s
///     per publish at 1,000 covers (plan Appendix A). A complete snapshot
///     (move, replacement) never reuses (CV4).
///  2. PRODUCE: a LOCAL cover (`covers/…` / `file://`) is read and
///     re-encoded; a REMOTE one is fetched (bounded, allow-listed hosts —
///     M09). Either way the bytes are sha-d, so the host uploads only what
///     really changed.
///  3. FALL BACK: no usable bytes, but the record holds the path → keep the
///     published file.
///  4. Nothing usable anywhere: the sanitized remote URL, or no cover.
///
/// Why step 1 is safe (beginner note): a stored cover file never changes
/// once saved — a new picture always gets a new file name (plan CV1, pinned
/// by `cover_files_immutable_test.dart`). So "same source" means "same
/// picture", and "same rendition" means "the same recipe made the file that
/// is online". Each decision also says which source the published file
/// really shows ([CoverDecision.source]); a fall-back file of unknown origin
/// records none, so the next publish tries that cover again.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_cover_names.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';

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
    this.source,
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

  /// The cover source (trimmed) the published file at [publishPath] really
  /// shows, made with the current rendition — what the record stores for
  /// this key. Null when no such file backs this decision.
  final String? source;
}

/// Decides covers for one publish run.
///
/// The cover NAMES arrive per call ([PublishCoverNames]), not through the
/// constructor: they come from the one salt read the snapshot builder makes
/// at the start of a build (plan D.5, CV8), so the decider never touches
/// the salt store itself.
final class PublishCoverDecider {
  /// Creates the decider over its ports.
  const PublishCoverDecider({
    required LocalCoverReader readLocalCover,
    required RemoteCoverFetcher fetchRemoteCover,
  }) : _readLocalCover = readLocalCover,
       _fetchRemoteCover = fetchRemoteCover;

  final LocalCoverReader _readLocalCover;
  final RemoteCoverFetcher _fetchRemoteCover;

  /// Decides the cover of one item: [coverUrl] is the source reference,
  /// [itemId] the identity the salted path is hashed from, [names] this
  /// publish's naming (one salt read).
  ///
  /// Beginner note: the salted path keeps every cover's file name stable
  /// across publishes (see `PublishCoverIds`); the manifest's
  /// sha/source-identity skips are what make a re-publish of an unchanged
  /// cover upload nothing.
  ///
  /// [mode] [PublishMode.complete] never reuses by source identity: a move
  /// or replacement reads every cover (plan CV4, ADR 0017 Decision 4).
  Future<CoverDecision> forItem(
    String? coverUrl, {
    required int itemId,
    required PublishCoverNames names,
    required PreviousPublication manifest,
    required PublishMode mode,
  }) => _decide(
    coverUrl,
    manifest,
    mode: mode,
    publishPath: () => names.pathFor(itemId),
    urlKey: '$itemId',
  );

  /// Decides the cover of one periodical, keyed on its stable uid (ADR 0014
  /// W4) — one series cover is ONE upload, referenced by the series entry
  /// and by every issue that falls back to it (`IssueCover.resolve`).
  Future<CoverDecision> forPeriodical(
    String? coverUrl, {
    required String periodicalUid,
    required PublishCoverNames names,
    required PreviousPublication manifest,
    required PublishMode mode,
  }) => _decide(
    coverUrl,
    manifest,
    mode: mode,
    publishPath: () => names.pathForPeriodical(periodicalUid),
    urlKey: 'periodical:$periodicalUid',
  );

  Future<CoverDecision> _decide(
    String? coverUrl,
    PreviousPublication manifest, {
    required PublishMode mode,
    required String Function() publishPath,
    required String urlKey,
  }) async {
    final src = coverUrl?.trim() ?? '';
    if (src.isEmpty) return const CoverDecision();
    final path = publishPath();
    final repoSha = manifest.shaFor(path);
    final recordedSource = manifest.coverSourceFor(urlKey);
    // True when the record's covers were made by this build's recipe, so a
    // recorded source names a file that is online in exactly that form.
    final sameRendition =
        manifest.reusableCoverRendition == PublishCoverRendition.current;

    // 1. REUSE, unread (CV2). Complete snapshots never take this branch.
    if (mode == PublishMode.incremental &&
        sameRendition &&
        repoSha != null &&
        recordedSource == src) {
      return CoverDecision(
        publishPath: path,
        reuseSha: repoSha,
        publishedCoverUrl: path,
        source: src,
      );
    }

    // 2. PRODUCE the bytes (read + re-encode, or bounded fetch).
    final local = CoverPaths.isLocal(src);
    final bytes = local
        ? await _readLocalCover(src)
        : await _fetchRemoteCover(src);
    if (bytes != null) {
      return CoverDecision(
        publishPath: path,
        bytes: bytes,
        gitSha: GitBlobSha.of(bytes),
        publishedCoverUrl: path,
        source: src,
      );
    }

    // 3. FALL BACK to the published file. It still shows what the record
    // said it shows — but only a current-rendition record can vouch for
    // that; otherwise no source is recorded and the next publish retries.
    if (repoSha != null) {
      return CoverDecision(
        publishPath: path,
        reuseSha: repoSha,
        publishedCoverUrl: path,
        source: sameRendition ? recordedSource : null,
      );
    }

    // 4. No usable cover bytes: fall back to a sanitized remote URL or drop.
    if (local) return const CoverDecision();
    return CoverDecision(publishedCoverUrl: CoverUrlAllowList.sanitize(src));
  }
}
