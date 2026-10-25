/// Reads the Pitaka JSON export (`PitakaExport`, up to schema v4). Pure Dart
/// port of Kotlin `PitakaJsonImporter` + the Moshi-reflective `PitakaExport`
/// shape, extended by ADR 0014 W1 for item kinds.
///
/// Key contract (verified against Kotlin source §3):
///  - Moshi reflective serialization uses **Kotlin property names** → camelCase
///    JSON keys (`titleTransliteration`, `publishedYear`, `coverUrl`, …).
///  - `schemaVersion` is read FIRST; a file newer than [kPitakaSchemaVersion]
///    is refused cleanly (update-channel rule).
///  - `ageGroup` is the stable token string, parsed tolerantly via
///    AgeGroup.fromToken (legacy names accepted; unknown becomes null).
///  - `sourceType` is the enum NAME (upper-case), parsed tolerantly.
///  - Imported rows get FRESH ids (id = 0); LOCAL cover references are dropped
///    unless keepLocalCovers is set (only the bundle path ships image bytes).
///  - Malformed input never throws — errors are collected into the payload.
///
/// v4 rules (ADR 0014 W1, fail closed on the unknown — P1):
///  - `kind` absent ⇒ `book`; an UNKNOWN kind token ⇒ the row is skipped and
///    counted, never mis-catalogued as a book (F6);
///  - `magazine-issue` without a nested `issue{}` ⇒ the row is rejected;
///  - an issue whose `periodicalUid` matches no periodical IN THE FILE is
///    imported as a plain book with a warning (its own fields survive; only
///    the series link is dropped);
///  - `periodicals[]` is parsed before `books[]` so the orphan check knows
///    every uid the file carries.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/import_export/domain/periodical_uid_ambiguity.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Highest `schemaVersion` this build can read (v4 = item kinds, ADR 0014 W1;
/// the Kotlin-era ceiling was 3).
const int kPitakaSchemaVersion = 4;

/// Parses Pitaka JSON export files into an [ImportPayload].
final class PitakaJsonImporter implements Importer, LibraryJsonParser {
  /// Creates a JSON importer. Bundles preserve local refs during parsing, then
  /// validate them against bundled bytes and rewrite them before persistence.
  const PitakaJsonImporter({
    this.keepLocalCovers = false,
    this.limits = ImportLimits.defaults,
  });

  /// When true, local `covers/<uuid>.jpg` / `file://` references are preserved
  /// instead of dropped. Plain JSON import keeps the default (false).
  final bool keepLocalCovers;

  /// Hostile-input caps (M4). Single source of truth: [ImportLimits.defaults].
  final ImportLimits limits;

  @override
  ImportPayload parse(String text) {
    // M4: reject an oversized file before handing it to jsonDecode, which would
    // otherwise materialise the whole structure in memory.
    if (text.length > limits.maxTextChars) {
      return const ImportPayload(
        parseErrors: ['File is too large to import safely.'],
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      return ImportPayload(parseErrors: ['Invalid JSON: ${e.message}']);
    }

    if (decoded is! Map<String, dynamic>) {
      return const ImportPayload(parseErrors: ['Empty or unparseable JSON.']);
    }

    final schemaVersion = _asInt(decoded['schemaVersion']) ?? 0;
    if (schemaVersion > kPitakaSchemaVersion) {
      final msg =
          'This file was created by a newer version of Pitak '
          '(schema v$schemaVersion). Update the app before importing.';
      return ImportPayload(
        parseErrors: [msg],
        tooNewSchemaVersion: schemaVersion,
      );
    }

    final books = <CatalogueItem>[];
    final periodicals = <Periodical>[];
    final wishlist = <WishlistBook>[];
    final errors = <String>[];
    final warnings = <String>[];

    // W1: periodicals FIRST — the orphan check on issues needs the set of
    // uids the file carries, regardless of key order inside the document.
    final filePeriodicalUids = <String>{};
    // Validation canonicalises UIDs, so the normalised rows cannot show that a
    // file spelled one identity two ways. The scan keeps the raw spellings
    // long enough to tell an exact duplicate (first row wins) from the fatal
    // trim-created collision.
    final uidScan = PeriodicalUidAmbiguityScan();
    var hasTrimCreatedUidCollision = false;
    final rawPeriodicals = decoded['periodicals'];
    if (rawPeriodicals is List) {
      for (var i = 0; i < rawPeriodicals.length; i++) {
        final item = rawPeriodicals[i];
        if (item is Map<String, dynamic>) {
          if (periodicals.length >= limits.maxRows) {
            errors.add(
              'Only the first ${limits.maxRows} magazine titles were '
              'imported; the rest were skipped.',
            );
            break;
          }
          final r = _RowReader('Magazine title', item, i + 1, limits, warnings);
          _periodical(r).match((errs) => errors.add(r.rowError(errs)), (p) {
            final uid = p.periodicalUid?.trim();
            if (uid != null && uid.isNotEmpty) filePeriodicalUids.add(uid);
            if (uidScan.isAmbiguous(_asString(item['periodicalUid']))) {
              hasTrimCreatedUidCollision = true;
            }
            periodicals.add(p);
          });
        }
      }
    }

    // M4: cap each collection's row count; drop the overflow with one error.
    // JSON key stays `books` (wire contract, ADR 0014); the payload field is
    // `items` because the list carries every catalogue item kind.
    final rawBooks = decoded['books'];
    if (rawBooks is List) {
      for (var i = 0; i < rawBooks.length; i++) {
        final item = rawBooks[i];
        if (item is Map<String, dynamic>) {
          if (books.length >= limits.maxRows) {
            errors.add(
              'Only the first ${limits.maxRows} books were imported; '
              'the rest were skipped.',
            );
            break;
          }
          final r = _RowReader('Book', item, i + 1, limits, warnings);
          _book(
            r,
            filePeriodicalUids,
          ).match((errs) => errors.add(r.rowError(errs)), books.add);
        }
      }
    }

    final rawWishlist = decoded['wishlist'];
    if (rawWishlist is List) {
      for (var i = 0; i < rawWishlist.length; i++) {
        final item = rawWishlist[i];
        if (item is Map<String, dynamic>) {
          if (wishlist.length >= limits.maxRows) {
            errors.add(
              'Only the first ${limits.maxRows} wishlist entries were '
              'imported; the rest were skipped.',
            );
            break;
          }
          final r = _RowReader('Wishlist entry', item, i + 1, limits, warnings);
          _wishlistBook(
            r,
          ).match((errs) => errors.add(r.rowError(errs)), wishlist.add);
        }
      }
    }

    return ImportPayload(
      items: books,
      periodicals: periodicals,
      wishlist: wishlist,
      parseErrors: errors,
      fatalErrors: [
        if (hasTrimCreatedUidCollision) kPeriodicalUidTrimCollisionMessage,
      ],
      warnings: warnings,
    );
  }

  /// Reads ONLY the merge namespace envelope (`libraryId`, `libraryName`) off a
  /// Pitaka JSON export, without parsing rows (PLAN-merge.md D40). Returns ''
  /// strings when absent/malformed — never throws. The merge gate validates the
  /// ID separately via `LibraryId.normalizeOrNull`, so a junk value here is
  /// safely treated as "no ID" (→ the differ-decision path).
  @override
  ({String libraryId, String libraryName}) parseEnvelope(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return (libraryId: '', libraryName: '');
      }
      return (
        libraryId: _asString(decoded['libraryId'])?.trim() ?? '',
        libraryName: _asString(decoded['libraryName'])?.trim() ?? '',
      );
    } on FormatException {
      return (libraryId: '', libraryName: '');
    }
  }

  /// Builds one [CatalogueItem] from a JSON row and validates it (M15): the row
  /// is either returned normalised or rejected with its field errors — never
  /// silently coerced. Over-long text is truncated + reported (D2); a
  /// disallowed cover link is dropped + reported.
  ///
  /// [filePeriodicalUids] is every series uid the file carries (parsed first),
  /// for the W1 orphan rule.
  Either<List<FieldError>, CatalogueItem> _book(
    _RowReader r,
    Set<String> filePeriodicalUids,
  ) {
    // Fresh id on import; drop LOCAL cover refs unless bundled. Remote https
    // covers are allow-list-checked by CatalogueItem.validate below.
    final unsafe = r.unsafeLocalCoverError(keepLocalCovers: keepLocalCovers);
    if (unsafe != null) return left([unsafe]);
    final cover = r.cover(keepLocalCovers: keepLocalCovers);

    // W1: the kind token decides the row's `details`. Absent ⇒ book; an
    // unknown token skips the row (F6 — never mis-catalogued as a book).
    final ItemDetails? details;
    final kindToken = _asString(r.raw['kind']);
    if (kindToken == null || kindToken.trim().isEmpty) {
      details = null;
    } else {
      switch (ItemKind.fromToken(kindToken)) {
        case null:
          return left([const FieldError('kind', 'is not a known kind')]);
        case ItemKind.book:
          details = null;
        case ItemKind.other:
          details = const OtherItemOf();
        case ItemKind.magazineIssue:
          final rawIssue = r.raw['issue'];
          if (rawIssue is! Map<String, dynamic>) {
            return left([
              const FieldError('issue', 'is required for a magazine issue'),
            ]);
          }
          final issue = _issue(rawIssue);
          if (filePeriodicalUids.contains(issue.periodicalUid.trim())) {
            details = issue;
          } else {
            // W1 orphan rule: the series is not in the file, so the issue
            // becomes a plain book (its base fields survive intact) with a
            // warning — the alternative (a dangling series link) would be
            // silent data corruption.
            r.warnings.add(
              '${r.kind} ${r.label}: its magazine title is not in the file; '
              'the row was imported as a book.',
            );
            details = null;
          }
      }
    }

    // M4: clamp every persisted text field so one giant cell can't bloat the
    // DB. M15/D2: clamping is now REPORTED as a warning, not silent.
    final candidate = CatalogueItem(
      title: r.text('title') ?? '',
      // JSON key stays `bookUid` (wire contract, ADR 0014).
      itemUid: r.text('bookUid'),
      titleTransliteration: r.text('titleTransliteration'),
      author: r.text('author'),
      isbn: r.text('isbn'),
      publisher: r.text('publisher'),
      publishedYear: _asInt(r.raw['publishedYear']),
      genre: r.text('genre'),
      coverUrl: cover,
      pageCount: _asInt(r.raw['pageCount']),
      language: r.text('language'),
      notes: r.text('notes'),
      location: r.text('location'),
      sourceType: ItemSourceTypeX.fromToken(_asString(r.raw['sourceType'])),
      sourceDetail: r.text('sourceDetail'),
      ageGroup: AgeGroup.fromToken(_asString(r.raw['ageGroup'])),
      addedDate: _asInt(r.raw['addedDate']) ?? 0,
      copyCount: _asInt(r.raw['copyCount']) ?? 1,
      needsMetadata: _asBool(r.raw['needsMetadata']) ?? false,
      removed: _asBool(r.raw['removed']) ?? false,
      removedAt: _asInt(r.raw['removedAt']),
      // M15: addedBy was the ONE text field that skipped the cap.
      addedBy: r.text('addedBy'),
      details: details,
    );
    // The gate appends the details' own `issue.*` errors, so a malformed
    // issue block rejects the row with field names that point at it.
    return CatalogueItem.validate(candidate).map((valid) {
      r.reportDroppedCover(valid.coverUrl, cover);
      return valid;
    });
  }

  /// Reads the nested `issue{}` object of a magazine-issue row (W1). Field
  /// rules (`periodicalUid` non-blank, a number or date present, a bound
  /// range in order) are enforced by `IssueOf.validate` downstream, not here.
  IssueOf _issue(Map<String, dynamic> raw) {
    return IssueOf(
      periodicalUid: _asString(raw['periodicalUid']) ?? '',
      volume: _asInt(raw['volume']),
      issueNumber: _asInt(raw['issueNumber']),
      issueDate: _asInt(raw['issueDate']),
      boundUntil: _asInt(raw['boundUntil']),
      label: _asString(raw['label']),
    );
  }

  /// Builds one [Periodical] from a JSON row and validates it — the same
  /// validate-or-reject contract as [_book] (the gate trims the title and
  /// canonicalises the ISSN).
  Either<List<FieldError>, Periodical> _periodical(_RowReader r) {
    final unsafe = r.unsafeLocalCoverError(keepLocalCovers: keepLocalCovers);
    if (unsafe != null) return left([unsafe]);
    final cover = r.cover(keepLocalCovers: keepLocalCovers);
    final candidate = Periodical(
      title: r.text('title') ?? '',
      periodicalUid: r.text('periodicalUid'),
      titleTransliteration: r.text('titleTransliteration'),
      issn: r.text('issn'),
      publisher: r.text('publisher'),
      language: r.text('language'),
      coverUrl: cover,
      frequency: PeriodicalFrequency.fromToken(_asString(r.raw['frequency'])),
      subscriptionStart: _asInt(r.raw['subscriptionStart']),
      subscriptionEnd: _asInt(r.raw['subscriptionEnd']),
      notes: r.text('notes'),
      location: r.text('location'),
      sourceType: ItemSourceTypeX.fromToken(_asString(r.raw['sourceType'])),
      sourceDetail: r.text('sourceDetail'),
      ageGroup: AgeGroup.fromToken(_asString(r.raw['ageGroup'])),
      addedDate: _asInt(r.raw['addedDate']) ?? 0,
      removed: _asBool(r.raw['removed']) ?? false,
      removedAt: _asInt(r.raw['removedAt']),
      addedBy: r.text('addedBy'),
    );
    return Periodical.validate(candidate).map((valid) {
      r.reportDroppedCover(valid.coverUrl, cover);
      return valid;
    });
  }

  /// Wishlist twin of [_book] — same validate-or-reject contract (M15).
  /// Local cover refs follow the same keepLocalCovers rule as books (the S6
  /// asymmetry let plain-JSON wishlist rows keep dangling local refs).
  Either<List<FieldError>, WishlistBook> _wishlistBook(_RowReader r) {
    final unsafe = r.unsafeLocalCoverError(keepLocalCovers: keepLocalCovers);
    if (unsafe != null) return left([unsafe]);
    final cover = r.cover(keepLocalCovers: keepLocalCovers);
    final candidate = WishlistBook(
      title: r.text('title') ?? '',
      titleTransliteration: r.text('titleTransliteration'),
      author: r.text('author'),
      isbn: r.text('isbn'),
      publisher: r.text('publisher'),
      publishedYear: _asInt(r.raw['publishedYear']),
      coverUrl: cover,
      priceEstimate: _asDouble(r.raw['priceEstimate']),
      priority: _asInt(r.raw['priority']) ?? WishlistBook.priorityMed,
      notes: r.text('notes'),
      source: WishlistSourceX.fromToken(_asString(r.raw['source'])),
      addedDate: _asInt(r.raw['addedDate']) ?? 0,
      purchased: _asBool(r.raw['purchased']) ?? false,
      purchasedDate: _asInt(r.raw['purchasedDate']),
      needsMetadata: _asBool(r.raw['needsMetadata']) ?? false,
    );
    return WishlistBook.validate(candidate).map((valid) {
      r.reportDroppedCover(valid.coverUrl, cover);
      return valid;
    });
  }

  // --- tolerant coercion helpers (never throw on a wrong-typed field) ---

  static String? _asString(Object? v) => v is String ? v : null;

  static int? _asInt(Object? v) {
    if (v is int) return v;
    // A JSON number like `1e400` decodes to double Infinity, and NaN/Infinity
    // `.toInt()` THROWS (UnsupportedError) — a hostile file must never crash
    // the parser, so only finite values in the int range are accepted.
    if (v is double) {
      if (!v.isFinite || v.abs() > 9007199254740991) return null;
      return v.toInt();
    }
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool? _asBool(Object? v) {
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    if (v is num) return v != 0;
    return null;
  }
}

/// Per-row read context for the JSON importer (M15): carries the raw row, its
/// 1-based position and the shared warnings sink so the field helpers can
/// produce messages that name the row. Pure string/number juggling — no IO.
final class _RowReader {
  _RowReader(this.kind, this.raw, this.rowNum, this.limits, this.warnings);

  /// "Book" or "Wishlist entry" — used in user-facing messages.
  final String kind;

  /// The raw JSON map for this row.
  final Map<String, dynamic> raw;

  /// 1-based row index within its collection.
  final int rowNum;

  /// Hostile-input caps (field length).
  final ImportLimits limits;

  /// Shared sink for non-fatal adjustments (truncations, dropped covers).
  final List<String> warnings;

  /// Reads a string field, truncated to the field cap; a truncation is
  /// reported (M15 D2: truncate + report, never silent).
  String? text(String field) {
    final value = raw[field];
    if (value is! String) return null;
    final clamped = limits.clampField(value);
    if (clamped != null && clamped.length != value.length) {
      warnings.add(
        '$kind $label: $field shortened to ${limits.maxFieldChars} '
        'characters.',
      );
    }
    return clamped;
  }

  /// Reads the cover reference: LOCAL refs are dropped unless the bundle mode
  /// asked to keep them; anything else is left for the entity validator to
  /// allow-list-check (its drop is reported via [reportDroppedCover]).
  String? cover({required bool keepLocalCovers}) {
    final value = raw['coverUrl'];
    if (value is! String) return null;
    if (!keepLocalCovers && CoverPaths.isLocal(value)) return null;
    return text('coverUrl');
  }

  /// In bundle mode a local-shaped but UNSAFE cover ref (`covers/../x.jpg`)
  /// is tampering evidence — our exporter never writes one — so the row is
  /// rejected (the bundle then fails closed, M04). In plain-JSON mode such
  /// refs are just dropped like any local ref, so this returns null there.
  FieldError? unsafeLocalCoverError({required bool keepLocalCovers}) {
    if (!keepLocalCovers) return null;
    final value = raw['coverUrl'];
    if (value is! String) return null;
    if (CoverPaths.isLocal(value) && CoverPaths.leafOf(value) == null) {
      return const FieldError('coverUrl', 'is not a safe cover reference');
    }
    return null;
  }

  /// Records a warning when validation dropped a cover link that was present
  /// in the file (a non-allow-listed remote URL or an unsafe local ref).
  void reportDroppedCover(String? validatedCover, String? parsedCover) {
    if (parsedCover != null && validatedCover == null) {
      warnings.add(
        '$kind $label: cover link is not from an allowed source and was '
        'left out.',
      );
    }
  }

  /// One line per rejected row, naming the row and every invalid field.
  String rowError(List<FieldError> errs) =>
      '$kind $label skipped: '
      '${errs.map((e) => '${e.field} ${e.problem}').join('; ')}.';

  /// A short human handle for the row: its title (truncated) plus the index.
  String get label {
    final t = raw['title'];
    final title = t is String ? t.trim() : '';
    final short = title.length > 40 ? '${title.substring(0, 40)}…' : title;
    return short.isEmpty ? '(row $rowNum)' : '"$short" (row $rowNum)';
  }
}
