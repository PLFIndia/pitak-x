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

import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/infrastructure/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Highest `schemaVersion` this build can read (Kotlin `SCHEMA_VERSION = 3`).
const int kPitakaSchemaVersion = 3;

/// Parses Pitaka JSON export files into an [ImportPayload].
final class PitakaJsonImporter implements Importer {
  /// Creates a JSON importer. [keepLocalCovers] is only set true by the bundle
  /// reader, which writes the bundled cover files to disk before parsing so the
  /// local references resolve.
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

    // M4: cap each collection's row count; drop the overflow with one error.
    final rawBooks = decoded['books'];
    if (rawBooks is List) {
      for (final item in rawBooks) {
        if (item is Map<String, dynamic>) {
          if (books.length >= limits.maxRows) {
            errors.add(
              'Only the first ${limits.maxRows} books were imported; '
              'the rest were skipped.',
            );
            break;
          }
          books.add(_book(item));
        }
      }
    }

    final rawWishlist = decoded['wishlist'];
    if (rawWishlist is List) {
      for (final item in rawWishlist) {
        if (item is Map<String, dynamic>) {
          if (wishlist.length >= limits.maxRows) {
            errors.add(
              'Only the first ${limits.maxRows} wishlist entries were '
              'imported; the rest were skipped.',
            );
            break;
          }
          wishlist.add(_wishlistBook(item));
        }
      }
    }

    return ImportPayload(
      books: books,
      wishlist: wishlist,
      parseErrors: errors,
    );
  }

  /// Reads ONLY the merge namespace envelope (`libraryId`, `libraryName`) off a
  /// Pitaka JSON export, without parsing rows (PLAN-merge.md D40). Returns ''
  /// strings when absent/malformed — never throws. The merge gate validates the
  /// ID separately via `LibraryId.normalizeOrNull`, so a junk value here is
  /// safely treated as "no ID" (→ the differ-decision path).
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

  Book _book(Map<String, dynamic> m) {
    // Fresh id on import; drop LOCAL cover refs unless bundled. Remote https
    // covers resolve anywhere, so they pass through in both modes.
    final rawCover = _asString(m['coverUrl']);
    final cover = (!keepLocalCovers && CoverPaths.isLocal(rawCover))
        ? null
        : limits.clampField(rawCover);
    // M4: clamp every persisted text field so one giant cell can't bloat the
    // DB.
    return Book(
      title: limits.clampField(_asString(m['title'])) ?? '',
      bookUid: limits.clampField(_asString(m['bookUid'])),
      titleTransliteration: limits.clampField(
        _asString(m['titleTransliteration']),
      ),
      author: limits.clampField(_asString(m['author'])),
      isbn: limits.clampField(_asString(m['isbn'])),
      publisher: limits.clampField(_asString(m['publisher'])),
      publishedYear: _asInt(m['publishedYear']),
      genre: limits.clampField(_asString(m['genre'])),
      coverUrl: cover,
      pageCount: _asInt(m['pageCount']),
      language: limits.clampField(_asString(m['language'])),
      notes: limits.clampField(_asString(m['notes'])),
      location: limits.clampField(_asString(m['location'])),
      sourceType: BookSourceTypeX.fromToken(_asString(m['sourceType'])),
      sourceDetail: limits.clampField(_asString(m['sourceDetail'])),
      ageGroup: AgeGroup.fromToken(_asString(m['ageGroup'])),
      addedDate: _asInt(m['addedDate']) ?? 0,
      copyCount: _asInt(m['copyCount']) ?? 1,
      needsMetadata: _asBool(m['needsMetadata']) ?? false,
      removed: _asBool(m['removed']) ?? false,
      removedAt: _asInt(m['removedAt']),
      addedBy: _asString(m['addedBy']),
    );
  }

  WishlistBook _wishlistBook(Map<String, dynamic> m) {
    return WishlistBook(
      title: limits.clampField(_asString(m['title'])) ?? '',
      titleTransliteration: limits.clampField(
        _asString(m['titleTransliteration']),
      ),
      author: limits.clampField(_asString(m['author'])),
      isbn: limits.clampField(_asString(m['isbn'])),
      publisher: limits.clampField(_asString(m['publisher'])),
      publishedYear: _asInt(m['publishedYear']),
      coverUrl: limits.clampField(_asString(m['coverUrl'])),
      priceEstimate: _asDouble(m['priceEstimate']),
      priority: _asInt(m['priority']) ?? WishlistBook.priorityMed,
      notes: limits.clampField(_asString(m['notes'])),
      source: WishlistSourceX.fromToken(_asString(m['source'])),
      addedDate: _asInt(m['addedDate']) ?? 0,
      purchased: _asBool(m['purchased']) ?? false,
      purchasedDate: _asInt(m['purchasedDate']),
      needsMetadata: _asBool(m['needsMetadata']) ?? false,
    );
  }

  // --- tolerant coercion helpers (never throw on a wrong-typed field) ---

  static String? _asString(Object? v) => v is String ? v : null;

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
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
