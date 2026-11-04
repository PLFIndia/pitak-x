/// Builds the CATALOGUE section of the site, once, for every host
/// (publish application layer, AGENTS.md §3.1/§4; Cloudflare plan R3/R7).
///
/// Why this exists (beginner note): before the Cloudflare plan the catalogue
/// bytes were assembled deep inside `PublishLibraryUseCase`, so a second host
/// would have needed a copy of that code — and two copies of a publisher drift
/// (one starts including a field the other forgets). This builder is the ONE
/// implementation: it produces the same files the GitHub flow has always
/// produced, and every host adapter consumes that result. The characterization
/// test (`catalogue_section_builder_test.dart`) pins the bytes.
///
/// Ownership (R7): this section owns `books.json`, `index.html`,
/// `library.json` and `covers/*` — nothing else. Deleting one section never
/// touches the other.
///
/// Pure application layer: no Flutter, no IO. Cover bytes arrive through the
/// injected decider, the viewer HTML through an injected builder and the JSON
/// encoder is injected, so the encoders stay in one place.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_cover.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_cover_artifact_writer.dart';
import 'package:pitaka/features/publish/application/site/publish_artifact_writer.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_periodical_links.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';
import 'package:pitaka/features/publish/domain/site/github_pages_no_jekyll.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart'
    show LocationSharing;
import 'package:pitaka/features/vault/domain/availability.dart';

/// Builds the viewer HTML from the bundled template with placeholders filled.
///
/// It takes the page settings PER CALL (fix-plan M8) instead of a closure that
/// captured them at DI time, so one operation uses one settings snapshot and a
/// failed settings write cannot break the builder itself.
typedef ViewerHtmlBuilderFn =
    Future<List<int>> Function({
      required String libraryName,
      required PublishContact contact,
      required LocationSharing sharing,
    });

/// Encodes the machine-readable payload (`books.json`).
typedef BooksJsonEncoder = List<int> Function(PublishExport export);

/// The ONE `books.json` encoder (pretty-printed UTF-8 JSON).
///
/// Why one implementation (beginner note): the bytes ARE the content sha, and
/// every host decides "upload or skip" by comparing that sha with the last
/// publish. Two encoders that differ by a single space would make every file
/// look changed on the other host and force a full re-upload — so production
/// wiring uses this function and never builds its own encoder.
List<int> encodeBooksJsonBytes(PublishExport export) =>
    utf8.encode(const JsonEncoder.withIndent('  ').convert(export.toJson()));

/// Builds the catalogue section for one publish.
final class CatalogueSectionBuilder {
  /// Creates the builder over its injected pieces.
  const CatalogueSectionBuilder({
    required PublishCoverDecider covers,
    required ViewerHtmlBuilderFn buildViewerHtml,
    required BooksJsonEncoder encodeBooksJson,
    PublishArtifactSink? sink,
  }) : _covers = covers,
       _buildViewerHtml = buildViewerHtml,
       _encodeBooksJson = encodeBooksJson,
       _sink = sink;

  final PublishCoverDecider _covers;
  final ViewerHtmlBuilderFn _buildViewerHtml;
  final BooksJsonEncoder _encodeBooksJson;
  final PublishArtifactSink? _sink;

  /// Uses the same builders with immediate artifact consumption (R24).
  CatalogueSectionBuilder withArtifactSink(PublishArtifactSink sink) =>
      CatalogueSectionBuilder(
        covers: _covers,
        buildViewerHtml: _buildViewerHtml,
        encodeBooksJson: _encodeBooksJson,
        sink: sink,
      );

  /// Repo path of the network descriptor (docs/ARCHITECTURE.md §5.1). One
  /// constant so the write, the sha-diff skip and the delete path agree.
  static const String libraryJsonPath = 'library.json';

  /// The machine-readable catalogue.
  static const String booksJsonPath = 'books.json';

  /// The human-readable viewer page.
  static const String indexHtmlPath = 'index.html';

  /// Shown when a persisted series/issue link cannot be resolved. Nothing is
  /// published in that case (fail closed: a half-linked catalogue is worse
  /// than no publish).
  static const String invalidLinksMessage =
      'Some magazine series or issue links are invalid. '
      'Nothing was published.';

  /// Shown when a COMPLETE publish cannot obtain usable cover bytes for an
  /// item that references a cover. A whole-site replacement must never omit a
  /// file the old site had (R2), so this fails before any write.
  static const String missingCoverMessage =
      'A cover image could not be read. Nothing was published.';

  /// Builds the section.
  ///
  /// [books] are all library items of any kind (removed ones are filtered
  /// here); [periodicals] are all magazine titles (a removed series gets no
  /// entry, but its issues are still live rows and keep the series-cover
  /// fallback). [activeLoanCounts] is null when the vault is locked
  /// (availability then omitted). [libraryJson] is the pre-encoded network
  /// descriptor, or null when none may be written — null REMOVES a previously
  /// published descriptor, so a stale location never outlives an opt-out.
  ///
  /// [naming] holds the public keys with their key-set id AND the cover
  /// names, all from ONE salt read (`PublishItemKeys.namingFor`, ADR 0019
  /// Decisions 3 and 4, plan D.5). Its keys are well-formed and unique by
  /// construction; every live item must have one, otherwise nothing is
  /// built (fail closed), because an item without its key could never be
  /// matched to `availability.json`. The key-set id is written as
  /// `books.json`'s top-level `keySet` (plan A.6 #68).
  ///
  /// [gitHubPagesSite] adds the empty `.nojekyll` (`GitHubPagesNoJekyll`,
  /// plan SP5); it is required so no caller can forget it, because a
  /// catalogue built without it would delete the recorded file again.
  Future<Either<Failure, PublishSection>> build({
    required List<CatalogueItem> books,
    required List<Periodical> periodicals,
    required Map<int, int>? activeLoanCounts,
    required List<int>? libraryJson,
    required bool gitHubPagesSite,
    required PublishPageSettings settings,
    required PreviousPublication previous,
    required int now,
    required PublishNaming naming,
    PublishMode mode = PublishMode.incremental,
    PublishTimingRecorder? timing,
  }) async {
    final library = books.where((b) => !b.removed).toList();

    // Resolve every link before cover IO or artifact construction. A
    // malformed persisted identity must never become an ungrouped or
    // partially covered file.
    final periodicalByUid = PublishPeriodicalLinks.resolve(
      books: library,
      periodicals: periodicals,
    );
    if (periodicalByUid == null) {
      return const Left(ValidationFailure(invalidLinksMessage));
    }

    // Keys are checked with the links, before any cover is read: like a bad
    // link, a missing or shared key stops the publish before any work or
    // write (ADR 0019 Decision 3).
    final keyCheck = _liveKeys(library, naming.keys);
    if (keyCheck case Left(value: final failure)) return Left(failure);
    final keys = keyCheck.toNullable()!;
    final names = naming.coverNames;
    // Removed series stay in periodicalByUid for issue cover fallback (D8),
    // but only live series publish a top-level entry.
    final publishedPeriodicals = periodicals.where((p) => !p.removed).toList();

    // A COMPLETE publish may not silently drop a referenced cover: every
    // decision below must end with a Pitak path backed by bytes or an explicit
    // trusted reuse record. A sanitized EXTERNAL URL is not an asset in this
    // snapshot and therefore cannot satisfy the gate (R2). Record the failure
    // (never throw for an expected failure) and return it before any write.
    Failure? missingCover;
    void requireCover(CoverDecision decision) {
      final hasMaterializedAsset =
          decision.publishPath != null &&
          (decision.bytes != null || decision.reuseSha != null);
      if (mode == PublishMode.complete && !hasMaterializedAsset) {
        missingCover = const ValidationFailure(missingCoverMessage);
      }
    }

    // Decide covers. A series cover is decided ONCE per publish and shared by
    // the series entry and every issue that falls back to it — `IssueCover`
    // resolves WHICH source an entry shows, the decider decides where that
    // source's bytes live.
    //
    // Plan S0: this is the stage that re-processes EVERY local cover on every
    // publish today, so it gets its own timing mark with the two counts that
    // matter (covers whose bytes had to be produced, versus covers reused from
    // the record). A null recorder makes the mark a no-op.
    final coverStartedAt = timing?.begin();
    final coverDecisions = <int, CoverDecision>{};
    final periodicalCoverDecisions = <String, CoverDecision>{};
    // One build-scoped writer consumes each cover BEFORE the next is read
    // and keeps only metadata for the original-order assembly below.
    final coverArtifacts = CatalogueCoverArtifactWriter(
      sink: _sink,
      previous: previous,
    );

    Future<Either<Failure, CoverDecision>> decidePeriodicalCover(
      Periodical series,
    ) async {
      final uid = series.periodicalUid!;
      final cached = periodicalCoverDecisions[uid];
      if (cached != null) return Right(cached);
      final decision = await _covers.forPeriodical(
        series.coverUrl,
        periodicalUid: uid,
        names: names,
        manifest: previous,
        mode: mode,
      );
      requireCover(decision);
      final written = await coverArtifacts.write(decision);
      if (written case Left(value: final failure)) return Left(failure);
      final kept = written.toNullable()!;
      periodicalCoverDecisions[uid] = kept;
      return Right(kept);
    }

    for (final book in library) {
      final series = periodicalByUid[book.issue?.periodicalUid];
      final resolved = IssueCover.resolve(book, series);
      if (resolved == null) continue;
      if (_isOwnCover(book, resolved)) {
        final decision = await _covers.forItem(
          book.coverUrl,
          itemId: book.id,
          names: names,
          manifest: previous,
          mode: mode,
        );
        requireCover(decision);
        final written = await coverArtifacts.write(decision);
        if (written case Left(value: final failure)) return Left(failure);
        coverDecisions[book.id] = written.toNullable()!;
      } else if (series != null) {
        final decided = await decidePeriodicalCover(series);
        if (decided case Left(value: final failure)) return Left(failure);
      }
    }
    // A published series with a cover of its own gets its decision even when
    // no issue falls back to it (the series entry shows it).
    for (final series in publishedPeriodicals) {
      if ((series.coverUrl?.trim() ?? '').isNotEmpty) {
        final decided = await decidePeriodicalCover(series);
        if (decided case Left(value: final failure)) return Left(failure);
      }
    }

    if (timing != null) {
      timing.end(
        PublishTimingStage.coverDecisions,
        coverStartedAt,
        coversRead: coverArtifacts.coversRead,
        coversReused: coverArtifacts.coversReused,
      );
    }

    if (missingCover case final failure?) return Left(failure);

    // What the record will say each published cover shows (ADR 0020): taken
    // from the DECISIONS, not from the rows, because only a decision knows
    // whether the file online really is the current rendition of this
    // source. A cover that fell back to an older file of unknown origin gets
    // no entry, so the next publish tries it again (plan CV2). Series covers
    // use the decider's 'periodical:' key so they never share the book id
    // key space. Taken now: the decision maps are cleared after assembly.
    final coverSources = <String, String>{
      for (final entry in coverDecisions.entries)
        if (entry.value.source case final source?) '${entry.key}': source,
      for (final entry in periodicalCoverDecisions.entries)
        if (entry.value.source case final source?)
          'periodical:${entry.key}': source,
    };

    final export = PublishExport(
      exportedAt: now,
      keySet: naming.keys.id,
      books: [
        for (final book in library)
          redactForPublish(
            book,
            availability: _availabilityFor(book, activeLoanCounts),
            resolveKey: (b) => keys[b.id],
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
      ],
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
    var booksJson = _encodeBooksJson(export);
    var viewerHtml = await _buildViewerHtml(
      libraryName: settings.libraryName,
      contact: settings.contact,
      sharing: settings.sharing,
    );

    // Assemble with per-file change detection. A sink consumes each artifact
    // immediately; without one, the original byte-bearing files are preserved.
    final desired = <PublishFile>[];
    Future<Failure?> addFile(PublishFile file) async {
      final written = await _write(file);
      final failure = written.swap().toNullable();
      if (failure != null) return failure;
      desired.add(written.toNullable()!);
      return null;
    }

    final coreFiles = <PublishFile>[
      _file(booksJsonPath, booksJson, previous),
      // The descriptor rides in the SAME atomic write as books.json: books,
      // descriptor and viewer always agree on the live site. Incremental
      // publish skips it when the bytes are unchanged (the codec's stable key
      // order makes equal input ⇒ equal blob sha).
      if (libraryJson != null) _file(libraryJsonPath, libraryJson, previous),
      _file(indexHtmlPath, viewerHtml, previous),
      // GitHub Pages skips its Jekyll step for this site (plan SP5). Empty
      // and unchanged after the first publish, so it uploads once.
      if (gitHubPagesSite)
        _file(GitHubPagesNoJekyll.path, GitHubPagesNoJekyll.bytes, previous),
    ];
    for (final file in coreFiles) {
      final failure = await addFile(file);
      if (failure != null) return Left(failure);
    }
    for (final d in [
      ...coverDecisions.values,
      ...periodicalCoverDecisions.values,
    ]) {
      final path = d.publishPath;
      final already = path == null ? null : coverArtifacts[path];
      if (already != null) {
        // Written when the decision was made; only its metadata goes in, in
        // this (the original) order.
        desired.add(already);
      } else if (d.bytes != null && path != null && d.gitSha != null) {
        final failure = await addFile(
          PublishFile(
            path: path,
            bytes: d.bytes!,
            gitSha: d.gitSha!,
            upload: previous.shaFor(path) != d.gitSha,
          ),
        );
        if (failure != null) return Left(failure);
      } else if (d.reuseSha != null && path != null) {
        desired.add(
          PublishFile(
            path: path,
            bytes: const [],
            gitSha: d.reuseSha!,
            upload: false,
          ),
        );
      }
    }
    // Do not retain every cover or the large catalogue JSON after consumption.
    coverDecisions.clear();
    periodicalCoverDecisions.clear();
    coverArtifacts.clear();
    booksJson = const [];
    viewerHtml = const [];
    // De-dup by path (deterministic: keep the first).
    final seen = <String>{};
    final files = [
      for (final f in desired)
        if (seen.add(f.path)) f,
    ];

    return right(
      PublishSection(
        section: SiteSection.catalogue,
        files: files,
        // Opt-out path (docs/ARCHITECTURE.md §5.1): with no descriptor to
        // write, a previously published library.json is deleted in the same
        // write — but only when this phone has a record of it (app-owned).
        deletePaths:
            libraryJson == null && previous.shaFor(libraryJsonPath) != null
            ? const [libraryJsonPath]
            : const [],
        coverUrlByKey: coverSources,
        // Every cover above was produced by this build's recipe, or reused
        // only because the record already said so (ADR 0020 Decision 3).
        coverRendition: PublishCoverRendition.current,
      ),
    );
  }

  /// One built file with its change flag derived from [previous].
  static PublishFile _file(
    String path,
    List<int> bytes,
    PreviousPublication previous,
  ) {
    final sha = GitBlobSha.of(bytes);
    return PublishFile(
      path: path,
      bytes: bytes,
      gitSha: sha,
      upload: previous.shaFor(path) != sha,
    );
  }

  Future<Either<Failure, PublishFile>> _write(PublishFile file) =>
      writePublishArtifact(sink: _sink, file: file);

  /// The inline tag, through the ONE rule (`isBookUnavailable`, ADR 0019
  /// Decision 1, plan A.6 #18). `notAvailableItemIds` uses the same function,
  /// so the inline tag and `availability.json` agree for the same counts.
  /// Null counts (vault locked) publish no tag, never "available".
  static String? _availabilityFor(CatalogueItem book, Map<int, int>? counts) {
    if (counts == null) return null;
    return isBookUnavailable(
          bookId: book.id,
          copyCount: book.copyCount,
          activeCounts: counts,
        )
        ? PublishItem.out
        : PublishItem.available;
  }

  /// The key of every live item, or the fixed refusal when one is missing.
  ///
  /// [itemKeys] cannot hold a malformed or shared key (`PublishKeySet`
  /// refuses both), but it may not cover every item, for example when the
  /// caller computed it for another list. Checking here keeps "every live
  /// item has its key" with the ONE `books.json` builder, whoever calls it.
  static Either<Failure, Map<int, String>> _liveKeys(
    List<CatalogueItem> library,
    PublishKeySet itemKeys,
  ) {
    final keys = <int, String>{};
    for (final item in library) {
      final key = itemKeys.keysById[item.id];
      if (key == null) {
        return const Left(ValidationFailure(PublishItemKeys.collisionMessage));
      }
      keys[item.id] = key;
    }
    return Right(keys);
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
