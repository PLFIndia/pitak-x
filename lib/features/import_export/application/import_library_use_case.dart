/// One-shot import use case (application layer, AGENTS.md §3.1). Port of
/// Kotlin `ImportLibraryUseCase`, with two additions from the 2026-09-03
/// review (decision Q9):
///
/// Sniffs the format, parses, and writes through both repositories. Dedup is
/// idempotent on re-import:
///  - library, matched by **itemUid** (the stable cross-device identity):
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
import 'package:pitaka/features/import_export/application/import_payload_guard.dart';
import 'package:pitaka/features/import_export/application/import_reconciliation.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/goodreads_csv_importer.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/cover_precedence.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/issue_identity.dart';
import 'package:pitaka/features/library/domain/merge/periodical_merge.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/issue_reprojection.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
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
    this.periodicalsAdded = 0,
    this.periodicalsUpdated = 0,
    this.periodicalsSkipped = 0,
    this.wishlistAdded = 0,
    this.wishlistReplaced = 0,
    this.parseErrors = const [],
    this.warnings = const [],
  });

  /// Detected format (null only when sniffing failed — a failure case).
  final ImportFormat? format;

  /// New library books inserted.
  final int booksAdded;

  /// Existing library books updated in place (same itemUid in the file).
  final int booksUpdated;

  /// Library items skipped because their ISBN or D6 issue identity is already
  /// owned, including duplicates claimed earlier in the same file.
  final int booksSkipped;

  /// New magazine titles inserted (schema v4, ADR 0014 W1).
  final int periodicalsAdded;

  /// Existing magazine titles updated in place (same periodicalUid in the
  /// file).
  final int periodicalsUpdated;

  /// Magazine titles skipped because their ISSN already existed or because an
  /// earlier valid row in the same file claimed the same series key.
  final int periodicalsSkipped;

  /// New wishlist entries inserted.
  final int wishlistAdded;

  /// Wishlist entries replaced (latest-wins) on an existing ISBN.
  final int wishlistReplaced;

  /// Per-row / file-level parse errors surfaced to the user.
  final List<String> parseErrors;

  /// Non-fatal adjustments applied to kept rows (M15: truncated fields,
  /// dropped cover links), surfaced alongside [parseErrors].
  final List<String> warnings;
}

/// Imports a text payload (JSON/CSV) or an already-parsed bundle payload.
final class ImportLibraryUseCase {
  /// Creates the use case over its collaborators.
  ///
  /// Not `const`: construction also builds the [ImportSeriesReconciler] the
  /// item pass reconciles against, which a constant initializer cannot hold.
  ImportLibraryUseCase({
    required CatalogueItemRepository bookRepo,
    required WishlistRepository wishlistRepo,
    // ADR 0014 W1: schema v4 payloads carry periodicals, applied before the
    // item rows so issues meet their series already in place.
    required PeriodicalRepository periodicalRepo,
    // N14: concrete JSON codec lives in infrastructure; injected via DI.
    required LibraryJsonParser jsonParser,
    GoodreadsCsvImporter goodreadsImporter = const GoodreadsCsvImporter(),
  }) : _bookRepo = bookRepo,
       _wishlistRepo = wishlistRepo,
       _periodicalRepo = periodicalRepo,
       _json = jsonParser,
       _goodreads = goodreadsImporter,
       _series = ImportSeriesReconciler(periodicals: periodicalRepo);

  final CatalogueItemRepository _bookRepo;
  final WishlistRepository _wishlistRepo;
  final PeriodicalRepository _periodicalRepo;
  final LibraryJsonParser _json;
  final GoodreadsCsvImporter _goodreads;

  /// S4: the series/issue reconciliation the item pass depends on.
  final ImportSeriesReconciler _series;

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
  ) async {
    final schemaTooNewFailure = payload.schemaTooNewFailure;
    if (schemaTooNewFailure != null) {
      return left<Failure, ImportSummary>(schemaTooNewFailure);
    }
    return _bookRepo.runInTransaction(() => _applyInside(payload, format));
  }

  Future<Either<Failure, ImportSummary>> _applyInside(
    ImportPayload payload,
    ImportFormat format, {
    BundleImportImages? images,
  }) async {
    final refusal = ImportPayloadGuard.refusal(payload);
    if (refusal != null) return left(refusal);

    var booksAdded = 0;
    var booksUpdated = 0;
    var booksSkipped = 0;
    var wishlistAdded = 0;
    var wishlistReplaced = 0;

    // W1: resolve and write the series FIRST, inside the same transaction, so
    // every issue row below meets its series already in place. The reconciler
    // also answers "which stored series does each incoming UID belong to?",
    // which is how an issue filed under a same-ISSN foreign UID follows the
    // local series home instead of pointing at a row that does not exist (S4).
    final resolved = await _series.resolve(
      rawSeries: payload.periodicals,
      itemsCarryIssues: payload.items.any((item) => item.issue != null),
      images: images,
    );
    if (resolved.isLeft()) {
      return resolved.map((_) => const ImportSummary(format: null));
    }
    final series = resolved.toNullable()!;

    final issueClaims = ImportIssueClaims();

    for (final rawBook in payload.items) {
      // M15 defence in depth: validate the parsed row, re-anchor it to the
      // winning series, then validate AGAIN because projection changes the
      // title and other inherited fields. No derived row bypasses the gate.
      final checked = _validatedItem(rawBook);
      if (checked.isLeft()) {
        return checked.map((_) => const ImportSummary(format: null));
      }
      final reconciled = reattachIncomingIssue(
        checked.toNullable()!,
        series.seriesByIncomingUid,
        series.storedByUid,
      );
      final checkedReconciled = _validatedItem(reconciled);
      if (checkedReconciled.isLeft()) {
        return checkedReconciled.map((_) => const ImportSummary(format: null));
      }
      final book = checkedReconciled.toNullable()!;
      // 1. Same stable identity already here → update that row in place.
      final uid = book.itemUid?.trim();
      if (uid != null && uid.isNotEmpty) {
        final byUid = await _bookRepo.findByUid(uid);
        if (byUid.isLeft()) {
          return byUid.map((_) => const ImportSummary(format: null));
        }
        final existing = byUid.toNullable();
        if (existing != null) {
          // Stable identity never grants permission to change kind. In
          // particular, a v3 row has no kind token and therefore parses as a
          // book; that must not erase a stored issue's detail row.
          if (existing.kind != book.kind) {
            return left(
              ValidationFailure(
                'An imported ${book.kind.token} row matches a stored '
                '${existing.kind.token} row with the same UID. Cross-kind '
                'updates are not allowed; the import was cancelled.',
              ),
            );
          }
          final prepared = images == null
              ? right<Failure, CatalogueItem>(book)
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
          final stored = updated.toNullable()!;
          images?.recordBook(stored);
          issueClaims.record(stored);
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
      // 3. A new item UID can still point at an issue already owned under
      //    another UID. Check D6 AFTER re-anchoring, and include claims made
      //    by earlier writes from this file. Date-only issues have no D6 key
      //    and deliberately keep their old additive behaviour.
      final issue = book.issue;
      final identity = issue == null ? null : issueIdentityKey(issue);
      if (identity != null) {
        if (issueClaims.isClaimed(identity)) {
          booksSkipped++;
          continue;
        }
        final owned = await _series.findOwnedIssue(identity);
        if (owned.isLeft()) {
          return owned.map((_) => const ImportSummary(format: null));
        }
        if (owned.toNullable() != null) {
          booksSkipped++;
          continue;
        }
      }

      // 4. New to this library → insert.
      final prepared = images == null
          ? right<Failure, CatalogueItem>(book)
          : await images.prepareBook(book);
      if (prepared.isLeft()) {
        return prepared.map((_) => const ImportSummary(format: null));
      }
      final inserted = await _bookRepo.insert(prepared.toNullable()!);
      if (inserted.isLeft()) {
        return inserted.map((_) => const ImportSummary(format: null));
      }
      final stored = inserted.toNullable()!;
      images?.recordBook(stored);
      issueClaims.record(stored);
      booksAdded++;
    }

    for (final rawW in payload.wishlist) {
      // M15 defence in depth, same as the book loop above.
      final checkedW = WishlistBook.validate(rawW);
      if (checkedW.isLeft()) {
        final errs = (checkedW as Left<List<FieldError>, WishlistBook>).value;
        return left(
          ValidationFailure(
            'A parsed wishlist entry failed validation: '
            '${errs.map((e) => '${e.field} ${e.problem}').join('; ')}.',
          ),
        );
      }
      final w = checkedW.toNullable()!;
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

    // D3: a same-UID series update changes the source of every issue's
    // projected fields, including issues absent from this file. Run LAST so
    // any read/validation/write failure rolls back series, items, wishlist,
    // and (through the bundle wrapper) staged covers together.
    final reprojected = await IssueReprojection(
      periodicals: _periodicalRepo,
      items: _bookRepo,
    ).callAll(series.updatedStored.values);
    if (reprojected.isLeft()) {
      return reprojected.map((_) => const ImportSummary(format: null));
    }

    return right(
      ImportSummary(
        format: format,
        booksAdded: booksAdded,
        booksUpdated: booksUpdated,
        booksSkipped: booksSkipped,
        periodicalsAdded: series.added,
        periodicalsUpdated: series.updated,
        periodicalsSkipped: series.skipped,
        wishlistAdded: wishlistAdded,
        wishlistReplaced: wishlistReplaced,
        parseErrors: payload.parseErrors,
        warnings: payload.warnings,
      ),
    );
  }

  /// The shared ingress gate for both the parsed row and its reprojected form.
  static Either<Failure, CatalogueItem> _validatedItem(
    CatalogueItem candidate,
  ) => CatalogueItem.validate(candidate).mapLeft(
    (errors) => ValidationFailure(
      'A parsed book failed validation: '
      '${errors.map((e) => '${e.field} ${e.problem}').join('; ')}.',
    ),
  );

  /// The row to write when [incoming] (same itemUid) updates [existing]:
  /// keep this device's `id` (vault loans reference it) and `itemUid`; take
  /// the incoming catalogue fields; the cover follows [resolveIncomingCover]
  /// (M09): a local photo is never replaced by an incoming remote URL, and
  /// a file carrying no cover keeps the local one.
  static CatalogueItem _mergeIntoExisting({
    required CatalogueItem existing,
    required CatalogueItem incoming,
  }) {
    final cover = resolveIncomingCover(
      existing: existing.coverUrl,
      incoming: incoming.coverUrl,
    );
    return CatalogueItem(
      id: existing.id,
      itemUid: existing.itemUid,
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
      // The caller has already proved both rows are the SAME kind. Incoming
      // details therefore replace same-kind values only; a missing v3 kind
      // can never delete a stored issue or other-item marker.
      details: incoming.details,
    );
  }
}
