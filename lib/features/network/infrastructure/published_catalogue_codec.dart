/// Defensive reader for the published `books.json` catalogue (network
/// infrastructure, pure Dart; ADR 0015, docs/ARCHITECTURE.md §5.6).
///
/// This is the hostile-input half of the published-catalogue feature. The
/// payload lives on anybody's public site, so every byte is untrusted. The
/// reader:
///  - refuses an oversized body BEFORE UTF-8/JSON decoding (defence in depth:
///    the transport enforces the same cap);
///  - refuses malformed UTF-8/JSON, excessive nesting, a non-map root, a
///    missing/non-integer/`<= 0` `schemaVersion`, or a missing/non-list
///    `books` — corruption is never confused with an empty catalogue;
///  - reads a NEWER schema forward-tolerantly: the fields this build
///    understands are decoded, unknown keys are ignored, and the model reports
///    `hasNewerSchema` so the UI keeps a visible warning (V6). A version is
///    never a reason to show nothing;
///  - stops at 100 000 rows per collection and records the truncation;
///  - returns `Either<PublishedCatalogueFailure, PublishedCatalogue>` and
///    NEVER throws for expected failures (AGENTS §5).
///
/// The limits are constructor fields (with the production defaults below) so a
/// boundary test can inject tiny caps instead of allocating 64 MiB; production
/// always uses the defaults. The row rules live in [PublishedItemReader]
/// (file-size ratchet, V16).
///
/// JSON stays in infrastructure: the domain receives clean published-view
/// models, and no DTO reaches presentation (AGENTS §3.3).
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_item_reader.dart';

/// The `books.json` reader (schema 1, forward-tolerant for newer schemas).
final class PublishedCatalogueCodec {
  /// Creates a reader with the given caps. Production uses the defaults below;
  /// tests inject small values to prove the boundary behaviour cheaply.
  const PublishedCatalogueCodec({
    this.maxBodyBytes = defaultMaxBodyBytes,
    this.maxRows = defaultMaxRows,
    this.maxJsonDepth = defaultMaxJsonDepth,
  });

  /// The schema version this build reads and writes (writer parity: the
  /// publish writer emits the same constant).
  static const int schemaVersion = publishedCatalogueSchemaVersion;

  /// Body cap: 64 MiB, matching the app's established outer interchange
  /// ceiling. This is an OUTER bound, not a performance promise — the UI must
  /// stay lazy (ADR 0015).
  static const int defaultMaxBodyBytes = 64 * 1024 * 1024;

  /// Max rows read from one collection (`books`, `periodicals`). Matches the
  /// app's established interchange ceiling; longer lists truncate visibly.
  static const int defaultMaxRows = 100000;

  /// Max JSON nesting accepted. A legitimate payload nests 4 deep
  /// (root → books array → item → issue); 32 is generous headroom that still
  /// stops a `[[[[…` stack-overflow bomb. The scan is string-aware, so
  /// brackets inside a quoted title never count.
  static const int defaultMaxJsonDepth = 32;

  /// Hard cap on the raw byte body (checked before any decoding).
  final int maxBodyBytes;

  /// Hard cap on rows per collection (extra rows are truncated and counted).
  final int maxRows;

  /// Hard cap on JSON nesting depth (a stack-overflow guard).
  final int maxJsonDepth;

  /// Parses catalogue bytes, enforcing every reader rule. Never throws.
  Either<PublishedCatalogueFailure, PublishedCatalogue> decode(
    List<int> bytes,
  ) {
    if (bytes.length > maxBodyBytes) {
      return _refuse(PublishedCatalogueFailureReason.tooLarge);
    }

    final Object? parsed;
    try {
      final text = utf8.decode(bytes);
      if (JsonNestingDepth.maxDepthOf(text) > maxJsonDepth) {
        return _refuse(PublishedCatalogueFailureReason.invalid);
      }
      parsed = jsonDecode(text);
    } on FormatException {
      // Bad UTF-8 or bad JSON — the only throws these decoders produce for
      // hostile input; both mean "not a catalogue".
      return _refuse(PublishedCatalogueFailureReason.invalid);
    }

    if (parsed is! Map<String, dynamic>) {
      return _refuse(PublishedCatalogueFailureReason.invalid);
    }

    final version = parsed['schemaVersion'];
    if (version is! int || version <= 0) {
      return _refuse(PublishedCatalogueFailureReason.invalid);
    }

    // `books` must be a list: a missing/wrong-typed collection is corruption,
    // not an empty library (an emptied library publishes `"books": []`).
    final rawBooks = parsed['books'];
    if (rawBooks is! List) {
      return _refuse(PublishedCatalogueFailureReason.invalid);
    }

    final tally = PublishedReadTally();
    final itemsTruncated = rawBooks.length > maxRows;
    final itemLimit = itemsTruncated ? maxRows : rawBooks.length;
    final items = <PublishedCatalogueItem>[];
    for (var i = 0; i < itemLimit; i++) {
      final item = PublishedItemReader.readItem(rawBooks[i], i, tally);
      if (item != null) items.add(item);
    }

    final periodicals = <PublishedPeriodical>[];
    var periodicalsTruncated = false;
    final rawPeriodicals = parsed['periodicals'];
    if (rawPeriodicals == null) {
      // Additive/legacy payload: no series block at all is normal.
      periodicalsTruncated = false;
    } else if (rawPeriodicals is! List) {
      // A corrupt block must not cost the readable books.
      tally.invalidOptionalFields++;
    } else {
      periodicalsTruncated = rawPeriodicals.length > maxRows;
      final limit = periodicalsTruncated ? maxRows : rawPeriodicals.length;
      // Insertion-ordered map = the HTML viewer's `Map.set` semantics: a
      // duplicate canonical uid keeps the FIRST position and the LAST valid
      // value, and every duplicate is counted so it is never merged silently.
      final byUid = <String, PublishedPeriodical>{};
      for (var i = 0; i < limit; i++) {
        final periodical = PublishedItemReader.readPeriodical(
          rawPeriodicals[i],
          tally,
        );
        if (periodical == null) continue;
        if (byUid.containsKey(periodical.periodicalUid)) {
          tally.duplicateSeriesUids++;
        }
        byUid[periodical.periodicalUid] = periodical;
      }
      periodicals.addAll(byUid.values);
    }

    // `exportedAt` is optional display metadata: an invalid value becomes
    // null plus a warning, never a rejection of otherwise readable items.
    int? exportedAt;
    var invalidExportedAt = false;
    final rawExportedAt = parsed['exportedAt'];
    if (rawExportedAt != null) {
      if (rawExportedAt is int &&
          CatalogueRules.isValidDateMillis(rawExportedAt)) {
        exportedAt = rawExportedAt;
      } else {
        invalidExportedAt = true;
      }
    }

    return Right(
      PublishedCatalogue(
        declaredSchemaVersion: version,
        exportedAt: exportedAt,
        items: items,
        periodicals: periodicals,
        warnings: tally.toWarnings(
          itemsTruncated: itemsTruncated,
          periodicalsTruncated: periodicalsTruncated,
          invalidExportedAt: invalidExportedAt,
        ),
      ),
    );
  }

  static Either<PublishedCatalogueFailure, PublishedCatalogue> _refuse(
    PublishedCatalogueFailureReason reason,
  ) => Left(PublishedCatalogueFailure(reason));
}
