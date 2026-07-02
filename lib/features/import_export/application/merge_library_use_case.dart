/// Multi-maintainer library merge (application layer, PLAN-merge.md).
///
/// Dart port of Kotlin `MergeLibraryUseCase`, adapted to this codebase's
/// conventions: it returns `Either<Failure, MergeOutcome>` (AGENTS.md §5 — no
/// throwing across layers) instead of Kotlin's throwing/sealed-only model, and
/// the pure reconciliation lives in `LibraryMergeEngine` (domain).
///
/// Unlike `ImportLibraryUseCase` (a one-shot "load a file into my library"),
/// this reconciles two catalogues maintained on different devices and converges
/// them, surfacing anything ambiguous for the user instead of guessing.
///
/// Two-stage flow:
///
///  STAGE 1 — library-ID gate (D40). Read the file's `libraryId`. If it MATCHES
///  this app's library ID, go straight to the engine merge ([MergeMerged]). If
///  it DIFFERS (or either side is blank / "unknown library"), do NOT merge
///  silently — return [MergeDiffersDecision] carrying the parsed books + both
///  library names, so the UI can ask the user to JOIN or OVERWRITE. This is the
///  namespace guard that stops a personal shelf and a community library from
///  cross-polluting.
///
///  STAGE 2 — apply. For a match, the engine has already auto-applied the
///  add-only union and surfaced conflicts/possible-duplicates. For a differ
///  decision the caller invokes `applyJoin` (non-destructive union + adopt the
///  incoming ID) or `applyOverwrite` (replace local catalogue + adopt the ID —
///  destructive, the guarded secondary).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/library_id.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// Result of an engine merge (library IDs matched, or applied via Join).
class MergeResult {
  /// Creates a merge result.
  const MergeResult({
    required this.added,
    required this.identical,
    required this.conflicts,
    required this.possibleDuplicates,
  });

  /// Books added automatically (add-only union).
  final int added;

  /// Matched + field-equal; no action taken.
  final int identical;

  /// Matched but differing — await user resolution.
  final List<MergeConflict> conflicts;

  /// No-ISBN fuzzy near-misses — await user confirmation.
  final List<PossibleDuplicate> possibleDuplicates;

  /// True when there is anything for the user to review.
  bool get hasReviewItems =>
      conflicts.isNotEmpty || possibleDuplicates.isNotEmpty;
}

/// Top-level outcome of [MergeLibraryUseCase.call].
sealed class MergeOutcome {
  const MergeOutcome();
}

/// Library IDs matched (or both empty-and-equal): engine merge already applied.
final class MergeMerged extends MergeOutcome {
  /// Creates a merged outcome.
  const MergeMerged(this.result);

  /// The applied merge result.
  final MergeResult result;
}

/// Library IDs DIFFER (D40). Nothing applied yet — the user must choose JOIN or
/// OVERWRITE. Carries the data needed to apply either, plus the names for a
/// legible warning.
final class MergeDiffersDecision extends MergeOutcome {
  /// Creates a differ-decision outcome.
  const MergeDiffersDecision({
    required this.incomingBooks,
    required this.incomingLibraryId,
    required this.incomingLibraryName,
    required this.localLibraryName,
    required this.localIsEmpty,
  });

  /// The parsed incoming books (not yet applied).
  final List<Book> incomingBooks;

  /// The incoming file's validated library ID (blank when absent/malformed).
  final String incomingLibraryId;

  /// The incoming file's library name (for the warning).
  final String incomingLibraryName;

  /// This app's library name (for the warning).
  final String localLibraryName;

  /// True when the local library has no books — overwrite is then safe.
  final bool localIsEmpty;
}

/// How the user chose to resolve one surfaced conflict / possible-duplicate.
enum MergeResolution {
  /// No-op: keep the local book unchanged.
  keepMine,

  /// Overwrite the local row in place (preserve id + uid; take their fields).
  takeTheirs,

  /// Insert the incoming book as a NEW separate row (fresh identity).
  keepBoth,
}

/// Reconciles an incoming Pitaka-JSON library file with the local catalogue.
final class MergeLibraryUseCase {
  /// Creates the use case over its collaborators.
  const MergeLibraryUseCase({
    required BookRepository bookRepo,
    required SettingsRepository settings,
    PitakaJsonImporter jsonImporter = const PitakaJsonImporter(),
  }) : _bookRepo = bookRepo,
       _settings = settings,
       _json = jsonImporter;

  final BookRepository _bookRepo;
  final SettingsRepository _settings;
  final PitakaJsonImporter _json;

  /// Runs the ID gate and (on a match) the engine merge.
  Future<Either<Failure, MergeOutcome>> call(String text) async {
    if (ImportFormatSniffer.detect(text) != ImportFormat.pitakaJson) {
      return left(
        const ValidationFailure(
          'Merge needs a Pitak library file (.json exported from Pitak). '
          'Other formats can be brought in with Import instead.',
        ),
      );
    }

    final payload = _json.parse(text);
    if (payload.books.isEmpty && payload.parseErrors.isNotEmpty) {
      return left(ValidationFailure(payload.parseErrors.first));
    }

    final envelope = _json.parseEnvelope(text);
    // A malformed/corrupt ID is treated as ABSENT (→ differ-decision path),
    // never silently merged, never adopted as junk.
    final incomingLibraryId =
        LibraryId.normalizeOrNull(envelope.libraryId) ?? '';
    final incomingLibraryName = envelope.libraryName;

    final localLibraryId = (await _settings.getOrCreateLibraryId()).trim();
    final settings = await _settings.load();

    // ID gate (D40). Match → merge. Differ (or incoming has no ID) → decision.
    final idsMatch =
        incomingLibraryId.isNotEmpty && incomingLibraryId == localLibraryId;
    if (!idsMatch) {
      final local = await _bookRepo.getAll();
      return local.flatMap(
        (books) => right(
          MergeDiffersDecision(
            incomingBooks: payload.books,
            incomingLibraryId: incomingLibraryId,
            incomingLibraryName: incomingLibraryName,
            localLibraryName: settings.libraryName,
            localIsEmpty: books.isEmpty,
          ),
        ),
      );
    }

    return (await _applyEngineMerge(payload.books)).map(MergeMerged.new);
  }

  /// JOIN (D40, the non-destructive default for a differ-IDs file): union the
  /// incoming books via the engine, AND adopt the incoming library ID + name so
  /// the two devices share a namespace going forward. Nobody loses data.
  Future<Either<Failure, MergeResult>> applyJoin(
    MergeDiffersDecision decision,
  ) async {
    if (decision.incomingLibraryId.isNotEmpty) {
      await _settings.setLibraryId(decision.incomingLibraryId);
      if (decision.incomingLibraryName.isNotEmpty) {
        await _settings.setLibraryName(decision.incomingLibraryName);
      }
    }
    return _applyEngineMerge(decision.incomingBooks);
  }

  /// OVERWRITE (D40, the guarded secondary): replace the local catalogue with
  /// the incoming one and adopt its library ID + name. Destructive — intended
  /// for a fresh/empty install becoming a clean replica. The caller is
  /// responsible for an explicit confirm before invoking this.
  Future<Either<Failure, Unit>> applyOverwrite(
    MergeDiffersDecision decision,
  ) async {
    final local = await _bookRepo.getAll();
    if (local.isLeft()) {
      return local.map((_) => unit);
    }
    // Snapshot ids first: deleting mutates the store, so iterating the live
    // list would risk concurrent modification.
    final existingIds = local
        .getOrElse((_) => const <Book>[])
        .map((b) => b.id)
        .toList();
    for (final id in existingIds) {
      final del = await _bookRepo.delete(id);
      if (del.isLeft()) return del;
    }
    for (final book in decision.incomingBooks) {
      final ins = await _bookRepo.insert(book.copyWith(id: Book.emptyId));
      if (ins.isLeft()) return ins.map((_) => unit);
    }
    if (decision.incomingLibraryId.isNotEmpty) {
      await _settings.setLibraryId(decision.incomingLibraryId);
      if (decision.incomingLibraryName.isNotEmpty) {
        await _settings.setLibraryName(decision.incomingLibraryName);
      }
    }
    return right(unit);
  }

  /// Applies the user's choice for one surfaced conflict / possible-duplicate.
  ///  - keep-mine   → no-op.
  ///  - take-theirs → overwrite the local row in place
  ///    (preserve local id + bookUid so identity is stable; take the incoming
  ///    catalogue fields).
  ///  - keep-both   → insert the incoming as a NEW separate
  ///    book with a FRESH identity (null uid so the mapper mints one; dropped
  ///    ISBN since it is unique and still held by the original row — D2: two
  ///    rows never share one ISBN).
  Future<Either<Failure, Unit>> applyResolution({
    required Book local,
    required Book incoming,
    required MergeResolution resolution,
  }) async {
    switch (resolution) {
      case MergeResolution.keepMine:
        return right(unit);
      case MergeResolution.takeTheirs:
        final updated = await _bookRepo.update(
          incoming.copyWith(id: local.id, bookUid: local.bookUid),
        );
        return updated.map((_) => unit);
      case MergeResolution.keepBoth:
        // copyWith cannot null a field (it uses `??`), and a true "keep both"
        // MUST drop the incoming uid + ISBN (both UNIQUE columns still held by
        // the original row) or the duplicate would collide. Build it fresh.
        final inserted = await _bookRepo.insert(_freshCopyOf(incoming));
        return inserted.map((_) => unit);
    }
  }

  /// A separate-entry copy of [b] with a CLEARED cross-device identity: no uid
  /// (the repo mints one), no ISBN (unique, still held by the original row),
  /// and an unset id (a brand-new row). Keeps every catalogue field.
  static Book _freshCopyOf(Book b) => Book(
    title: b.title,
    titleTransliteration: b.titleTransliteration,
    author: b.author,
    publisher: b.publisher,
    publishedYear: b.publishedYear,
    genre: b.genre,
    coverUrl: b.coverUrl,
    pageCount: b.pageCount,
    language: b.language,
    notes: b.notes,
    location: b.location,
    sourceType: b.sourceType,
    sourceDetail: b.sourceDetail,
    ageGroup: b.ageGroup,
    addedDate: b.addedDate,
    copyCount: b.copyCount,
    needsMetadata: b.needsMetadata,
    removed: b.removed,
    removedAt: b.removedAt,
    addedBy: b.addedBy,
  );

  /// Runs the engine against the current library and auto-applies the add-only
  /// union (the new rows get fresh ids but KEEP their uid so future merges
  /// reconcile). Conflicts + possible-duplicates are returned, not applied.
  Future<Either<Failure, MergeResult>> _applyEngineMerge(
    List<Book> incoming,
  ) async {
    final localRes = await _bookRepo.getAll();
    if (localRes.isLeft()) {
      return localRes.map(
        (_) => const MergeResult(
          added: 0,
          identical: 0,
          conflicts: [],
          possibleDuplicates: [],
        ),
      );
    }
    final local = localRes.getOrElse((_) => const <Book>[]);
    final plan = planMerge(local, incoming);
    for (final book in plan.toAdd) {
      final ins = await _bookRepo.insert(book.copyWith(id: Book.emptyId));
      if (ins.isLeft()) {
        return ins.map(
          (_) => const MergeResult(
            added: 0,
            identical: 0,
            conflicts: [],
            possibleDuplicates: [],
          ),
        );
      }
    }
    return right(
      MergeResult(
        added: plan.toAdd.length,
        identical: plan.identical,
        conflicts: plan.conflicts,
        possibleDuplicates: plan.possibleDuplicates,
      ),
    );
  }
}
