/// Reads the Pitaka JSON export (`PitakaExport`, schema v3). Pure Dart port of
/// Kotlin `PitakaJsonImporter` + the Moshi-reflective `PitakaExport` shape.
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
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Highest `schemaVersion` this build can read (Kotlin `SCHEMA_VERSION = 3`).
const int kPitakaSchemaVersion = 3;

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
      return ImportPayload(parseErrors: [msg]);
    }

    final books = <Book>[];
    final wishlist = <WishlistBook>[];
    final errors = <String>[];
    final warnings = <String>[];

    // M4: cap each collection's row count; drop the overflow with one error.
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
          _book(r).match((errs) => errors.add(r.rowError(errs)), books.add);
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
      books: books,
      wishlist: wishlist,
      parseErrors: errors,
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

  /// Builds one [Book] from a JSON row and validates it (M15): the row is
  /// either returned normalised or rejected with its field errors — never
  /// silently coerced. Over-long text is truncated + reported (D2); a
  /// disallowed cover link is dropped + reported.
  Either<List<FieldError>, Book> _book(_RowReader r) {
    // Fresh id on import; drop LOCAL cover refs unless bundled. Remote https
    // covers are allow-list-checked by Book.validate below.
    final unsafe = r.unsafeLocalCoverError(keepLocalCovers: keepLocalCovers);
    if (unsafe != null) return left([unsafe]);
    final cover = r.cover(keepLocalCovers: keepLocalCovers);
    // M4: clamp every persisted text field so one giant cell can't bloat the
    // DB. M15/D2: clamping is now REPORTED as a warning, not silent.
    final candidate = Book(
      title: r.text('title') ?? '',
      bookUid: r.text('bookUid'),
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
      sourceType: BookSourceTypeX.fromToken(_asString(r.raw['sourceType'])),
      sourceDetail: r.text('sourceDetail'),
      ageGroup: AgeGroup.fromToken(_asString(r.raw['ageGroup'])),
      addedDate: _asInt(r.raw['addedDate']) ?? 0,
      copyCount: _asInt(r.raw['copyCount']) ?? 1,
      needsMetadata: _asBool(r.raw['needsMetadata']) ?? false,
      removed: _asBool(r.raw['removed']) ?? false,
      removedAt: _asInt(r.raw['removedAt']),
      // M15: addedBy was the ONE text field that skipped the cap.
      addedBy: r.text('addedBy'),
    );
    return Book.validate(candidate).map((valid) {
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
