/// One-shot import use case (application layer, AGENTS.md §3.1). Port of
/// Kotlin `ImportLibraryUseCase`, with two additions from the 2026-09-03
/// review (decision Q9):
///
/// Sniffs the format, parses, and writes through both repositories. Dedup is
/// idempotent on re-import:
///  - library, matched by **bookUid** (the stable cross-device identity):
///    the existing row is **updated in place** — same id, same uid, so vault
///    loans keep pointing at it — with the incoming catalogue fields. A
///    local cover is kept when the incoming file has none (plain JSON drops
///    local cover refs, so a re-import must not blank your covers);
///  - library, matched by **ISBN** only (no uid match): **skipped** (you
///    already own it), exactly as before;
///  - wishlist: an existing ISBN is **replaced** latest-wins, keeping the
///    existing row's id + addedDate.
///
/// The whole apply runs in ONE database transaction: a failure on row N (e.g.
/// a UNIQUE collision in a crafted file) rolls back rows 1..N-1 too, so an
/// import is all-or-nothing and the reported counts always match the DB.
///
/// Bundles are validated without IO, then imported with operation-owned cover
/// files. File ownership lasts until the outermost database transaction ends.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/bundle_import_images.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/goodreads_csv_importer.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Result of an import run.
class ImportSummary {
  /// Creates a summary.
  const ImportSummary({
    required this.format,
    this.booksAdded = 0,
    this.booksUpdated = 0,
    this.booksSkipped = 0,
    this.wishlistAdded = 0,
    this.wishlistReplaced = 0,
    this.parseErrors = const [],
  });

  /// Detected format (null only when sniffing failed — a failure case).
  final ImportFormat? format;

  /// New library books inserted.
  final int booksAdded;

  /// Existing library books updated in place (same bookUid in the file).
  final int booksUpdated;

  /// Library books skipped because their ISBN already existed (no uid match).
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
    // N14: concrete JSON codec lives in infrastructure; injected via DI.
    required LibraryJsonParser jsonParser,
    GoodreadsCsvImporter goodreadsImporter = const GoodreadsCsvImporter(),
  }) : _bookRepo = bookRepo,
       _wishlistRepo = wishlistRepo,
       _json = jsonParser,
       _goodreads = goodreadsImporter;

  final BookRepository _bookRepo;
  final WishlistRepository _wishlistRepo;
  final LibraryJsonParser _json;
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
        return _applyPayload(_json.parse(text), format);
      case ImportFormat.goodreadsCsv:
        return _applyPayload(_goodreads.parse(text), format);
      case ImportFormat.pitakaBundle:
        return right(
          const ImportSummary(
            format: null,
            parseErrors: ['Bundle files are imported as a ZIP, not as text.'],
          ),
        );
    }
  }

  /// Imports a validated bundle. Cleanup owns only new files, never old covers.
  /// Do not invoke inside another database transaction: ownership is released
  /// only when this top-level operation knows that the commit succeeded.
  Future<Either<Failure, ImportSummary>> importBundle(
    ImportBundle bundle, {
    required BundleCoverFiles coverFiles,
    required CoverFileCoordinator coordinator,
  }) => coordinator.run(() async {
    final batch = coverFiles.begin();
    final images = BundleImportImages(bundle, batch);
    Either<Failure, ImportSummary> result;
    try {
      result = await _bookRepo.runInTransaction(() async {
        final applied = await _applyInside(
          bundle.payload,
          ImportFormat.pitakaBundle,
          images: images,
        );
        if (applied.isLeft()) return applied;
        final retained = await images.retainFinalReferences();
        return retained.match(left, (_) => applied);
      });
    } on Object {
      // Unexpected collaborator errors still release newly created files.
      result = left(const UnexpectedFailure('Bundle import failed.'));
    }
    if (result.isRight()) {
      // No IO: an already committed import cannot be undone here.
      batch.commit();
      return result;
    }
    final cleanup = await batch.rollback();
    return cleanup.match(left, (_) => result);
  });

  Future<Either<Failure, ImportSummary>> _applyPayload(
    ImportPayload payload,
    ImportFormat format,
  ) => _bookRepo.runInTransaction(() => _applyInside(payload, format));

  Future<Either<Failure, ImportSummary>> _applyInside(
    ImportPayload payload,
    ImportFormat format, {
    BundleImportImages? images,
  }) async {
    var booksAdded = 0;
    var booksUpdated = 0;
    var booksSkipped = 0;
    var wishlistAdded = 0;
    var wishlistReplaced = 0;

    for (final book in payload.books) {
      // 1. Same stable identity already here → update that row in place.
      final uid = book.bookUid?.trim();
      if (uid != null && uid.isNotEmpty) {
        final byUid = await _bookRepo.findByUid(uid);
        if (byUid.isLeft()) {
          return byUid.map((_) => const ImportSummary(format: null));
        }
        final existing = byUid.toNullable();
        if (existing != null) {
          final prepared = images == null
              ? right<Failure, Book>(book)
              : await images.prepareBook(book);
          if (prepared.isLeft()) {
            return prepared.map((_) => const ImportSummary(format: null));
          }
          final updated = await _bookRepo.update(
            _mergeIntoExisting(
              existing: existing,
              incoming: prepared.toNullable()!,
            ),
          );
          if (updated.isLeft()) {
            return updated.map((_) => const ImportSummary(format: null));
          }
          images?.recordBook(updated.toNullable()!);
          booksUpdated++;
          continue;
        }
      }
      // 2. Same ISBN (a different copy of a book you own) → skip.
      final isbn = book.isbn?.trim();
      if (isbn != null && isbn.isNotEmpty) {
        final found = await _bookRepo.findByIsbn(isbn);
        if (found.isLeft()) {
          return found.map((_) => const ImportSummary(format: null));
        }
        if (found.toNullable() != null) {
          booksSkipped++;
          continue;
        }
      }
      // 3. New to this library → insert.
      final prepared = images == null
          ? right<Failure, Book>(book)
          : await images.prepareBook(book);
      if (prepared.isLeft()) {
        return prepared.map((_) => const ImportSummary(format: null));
      }
      final inserted = await _bookRepo.insert(prepared.toNullable()!);
      if (inserted.isLeft()) {
        return inserted.map((_) => const ImportSummary(format: null));
      }
      images?.recordBook(inserted.toNullable()!);
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
          final prepared = images == null
              ? right<Failure, WishlistBook>(replacement)
              : await images.prepareWishlist(replacement);
          if (prepared.isLeft()) {
            return prepared.map((_) => const ImportSummary(format: null));
          }
          final res = await _wishlistRepo.upsert(prepared.toNullable()!);
          if (res.isLeft()) {
            return res.map((_) => const ImportSummary(format: null));
          }
          // upsert's conflict-update path may return SQLite's last insert ID;
          // the matched row's ID is the authoritative identity for replacement.
          images?.recordWishlist(res.toNullable()!.copyWith(id: existing.id));
          wishlistReplaced++;
          continue;
        }
      }
      final prepared = images == null
          ? right<Failure, WishlistBook>(w)
          : await images.prepareWishlist(w);
      if (prepared.isLeft()) {
        return prepared.map((_) => const ImportSummary(format: null));
      }
      final res = await _wishlistRepo.insert(prepared.toNullable()!);
      if (res.isLeft()) {
        return res.map((_) => const ImportSummary(format: null));
      }
      images?.recordWishlist(res.toNullable()!);
      wishlistAdded++;
    }

    return right(
      ImportSummary(
        format: format,
        booksAdded: booksAdded,
        booksUpdated: booksUpdated,
        booksSkipped: booksSkipped,
        wishlistAdded: wishlistAdded,
        wishlistReplaced: wishlistReplaced,
        parseErrors: payload.parseErrors,
      ),
    );
  }

  /// The row to write when [incoming] (same bookUid) updates [existing]:
  /// keep this device's `id` (vault loans reference it) and `bookUid`; take
  /// the incoming catalogue fields; keep the local cover when the file
  /// carries none (plain-JSON exports drop local cover references).
  static Book _mergeIntoExisting({
    required Book existing,
    required Book incoming,
  }) {
    final cover = incoming.coverUrl == null || incoming.coverUrl!.trim().isEmpty
        ? existing.coverUrl
        : incoming.coverUrl;
    return Book(
      id: existing.id,
      bookUid: existing.bookUid,
      title: incoming.title,
      titleTransliteration: incoming.titleTransliteration,
      author: incoming.author,
      isbn: incoming.isbn,
      publisher: incoming.publisher,
      publishedYear: incoming.publishedYear,
      genre: incoming.genre,
      coverUrl: cover,
      pageCount: incoming.pageCount,
      language: incoming.language,
      notes: incoming.notes,
      location: incoming.location,
      sourceType: incoming.sourceType,
      sourceDetail: incoming.sourceDetail,
      ageGroup: incoming.ageGroup,
      addedDate: incoming.addedDate == 0
          ? existing.addedDate
          : incoming.addedDate,
      copyCount: incoming.copyCount,
      needsMetadata: incoming.needsMetadata,
      removed: incoming.removed,
      removedAt: incoming.removedAt,
      addedBy: incoming.addedBy ?? existing.addedBy,
    );
  }
}
