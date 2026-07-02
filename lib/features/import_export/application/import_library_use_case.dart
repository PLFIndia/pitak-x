/// One-shot import use case (application layer, AGENTS.md §3.1). Pure port of
/// Kotlin `ImportLibraryUseCase`.
///
/// Sniffs the format, parses, and writes through both repositories. Dedup by
/// ISBN is idempotent on re-import:
///  - library: an existing ISBN is **skipped** (you already own it);
///  - wishlist: an existing ISBN is **replaced** latest-wins, keeping the
///    existing row's id + addedDate.
///
/// Bundles (.zip) are not plain text — they are read by `LibraryBundleReader`
/// and the parsed payload handed to `applyPayload` with the bundle format.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/goodreads_csv_importer.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Result of an import run.
class ImportSummary {
  /// Creates a summary.
  const ImportSummary({
    required this.format,
    this.booksAdded = 0,
    this.booksSkipped = 0,
    this.wishlistAdded = 0,
    this.wishlistReplaced = 0,
    this.parseErrors = const [],
  });

  /// Detected format (null only when sniffing failed — a failure case).
  final ImportFormat? format;

  /// New library books inserted.
  final int booksAdded;

  /// Library books skipped because their ISBN already existed.
  final int booksSkipped;

  /// New wishlist entries inserted.
  final int wishlistAdded;

  /// Wishlist entries replaced (latest-wins) on an existing ISBN.
  final int wishlistReplaced;

  /// Per-row / file-level parse errors surfaced to the user.
  final List<String> parseErrors;
}

/// Imports a text payload (JSON/CSV) or an already-parsed bundle payload.
final class ImportLibraryUseCase {
  /// Creates the use case over its collaborators.
  const ImportLibraryUseCase({
    required BookRepository bookRepo,
    required WishlistRepository wishlistRepo,
    PitakaJsonImporter jsonImporter = const PitakaJsonImporter(),
    GoodreadsCsvImporter goodreadsImporter = const GoodreadsCsvImporter(),
  }) : _bookRepo = bookRepo,
       _wishlistRepo = wishlistRepo,
       _json = jsonImporter,
       _goodreads = goodreadsImporter;

  final BookRepository _bookRepo;
  final WishlistRepository _wishlistRepo;
  final PitakaJsonImporter _json;
  final GoodreadsCsvImporter _goodreads;

  /// Sniffs [text], parses with the right importer, and applies it.
  Future<Either<Failure, ImportSummary>> importText(String text) async {
    final format = ImportFormatSniffer.detect(text);
    if (format == null) {
      return right(
        const ImportSummary(
          format: null,
          parseErrors: ['Unrecognized file format.'],
        ),
      );
    }
    switch (format) {
      case ImportFormat.pitakaJson:
        return applyPayload(_json.parse(text), format);
      case ImportFormat.goodreadsCsv:
        return applyPayload(_goodreads.parse(text), format);
      case ImportFormat.pitakaBundle:
        return right(
          const ImportSummary(
            format: null,
            parseErrors: ['Bundle files are imported as a ZIP, not as text.'],
          ),
        );
    }
  }

  /// Writes an already-parsed [payload] through both repositories with the
  /// dedup semantics. Shared by the text path and the bundle path.
  Future<Either<Failure, ImportSummary>> applyPayload(
    ImportPayload payload,
    ImportFormat format,
  ) async {
    var booksAdded = 0;
    var booksSkipped = 0;
    var wishlistAdded = 0;
    var wishlistReplaced = 0;

    for (final book in payload.books) {
      final isbn = book.isbn?.trim();
      if (isbn != null && isbn.isNotEmpty) {
        final found = await _bookRepo.findByIsbn(isbn);
        final existing = found.toNullable();
        if (found.isLeft()) {
          return found.map((_) => const ImportSummary(format: null));
        }
        if (existing != null) {
          booksSkipped++;
          continue;
        }
      }
      final inserted = await _bookRepo.insert(book);
      if (inserted.isLeft()) {
        return inserted.map((_) => const ImportSummary(format: null));
      }
      booksAdded++;
    }

    for (final w in payload.wishlist) {
      final isbn = w.isbn?.trim();
      if (isbn != null && isbn.isNotEmpty) {
        final found = await _wishlistRepo.findByIsbn(isbn);
        if (found.isLeft()) {
          return found.map((_) => const ImportSummary(format: null));
        }
        final existing = found.toNullable();
        if (existing != null) {
          // Replace latest-wins, preserving the existing id + addedDate.
          final replacement = w.copyWith(
            id: existing.id,
            addedDate: existing.addedDate,
          );
          final res = await _wishlistRepo.upsert(replacement);
          if (res.isLeft()) {
            return res.map((_) => const ImportSummary(format: null));
          }
          wishlistReplaced++;
          continue;
        }
      }
      final res = await _wishlistRepo.insert(w);
      if (res.isLeft()) {
        return res.map((_) => const ImportSummary(format: null));
      }
      wishlistAdded++;
    }

    return right(
      ImportSummary(
        format: format,
        booksAdded: booksAdded,
        booksSkipped: booksSkipped,
        wishlistAdded: wishlistAdded,
        wishlistReplaced: wishlistReplaced,
        parseErrors: payload.parseErrors,
      ),
    );
  }
}
