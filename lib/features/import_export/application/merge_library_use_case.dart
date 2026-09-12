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
///
/// N07 (astra-review.md) — three rules every apply path follows:
///  1. **Data first, identity second.** The incoming library ID is adopted
///     only AFTER the books have landed. A failed insert therefore leaves
///     this device's identity untouched — the next merge of the same file
///     still stops at the Join decision instead of auto-applying under an
///     adopted-but-empty namespace.
///  2. **Identity goes through its owner.** Adoption calls the
///     [LibraryNamespace] port (implemented by `SettingsController`), never
///     the settings repository directly, so the in-memory settings every
///     screen watches update with the disk.
///  3. **Nothing is silently dropped.** Rows the parser rejected (M15) and
///     the adjustments it made ride along in [MergeResult.skippedRows] /
///     [MergeResult.adjustments]; an identity adoption that failed after the
///     data landed is reported in [MergeResult.namespace] instead of turning
///     a successful merge into an error.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_plan.dart';
import 'package:pitaka/features/library/domain/cover_precedence.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/library_id.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';

/// What happened to this device's library identity during an apply (N07).
enum MergeNamespaceOutcome {
  /// The IDs already matched — nothing to adopt.
  unchanged,

  /// The incoming ID (and name, when present) was adopted.
  adopted,

  /// The books landed but the identity write failed. This device still has
  /// its OLD ID: the next merge from the same library will ask to Join again
  /// (every row will then be identical, so only the identity is adopted).
  adoptionFailed,
}

/// Result of an applied merge: the engine union (IDs matched or Join), or a
/// full replacement (Overwrite). Carries every omission the user should know
/// about — skipped rows, adjustments, review items, identity outcome — so the
/// page never describes a partial merge as simply "complete" (N07).
class MergeResult {
  /// Creates a merge result.
  const MergeResult({
    required this.added,
    required this.identical,
    required this.conflicts,
    required this.possibleDuplicates,
    this.replaced = false,
    this.skippedRows = const [],
    this.adjustments = const [],
    this.namespace = MergeNamespaceOutcome.unchanged,
  });

  /// Books added automatically (add-only union), or — for a replacement — the
  /// number of books now on this device.
  final int added;

  /// Matched + field-equal; no action taken.
  final int identical;

  /// Matched but differing — await user resolution.
  final List<MergeConflict> conflicts;

  /// No-ISBN fuzzy near-misses and in-file key collisions — await user
  /// confirmation.
  final List<PossibleDuplicate> possibleDuplicates;

  /// True when the local catalogue was REPLACED (Overwrite) rather than
  /// unioned. The page must not present this as "books added".
  final bool replaced;

  /// Rows in the file the parser REJECTED (M15) — they are not on this device.
  /// M15's own messages: row number, a short title so the user can find the
  /// row, and the field names at fault — never the invalid values themselves.
  final List<String> skippedRows;

  /// Non-fatal changes the parser made to kept rows (M15: shortened text,
  /// dropped cover links).
  final List<String> adjustments;

  /// What happened to the library identity.
  final MergeNamespaceOutcome namespace;

  /// True when there is anything for the user to review.
  bool get hasReviewItems =>
      conflicts.isNotEmpty || possibleDuplicates.isNotEmpty;

  /// True when the summary must explain something beyond the counts.
  bool get hasOmissions =>
      skippedRows.isNotEmpty ||
      adjustments.isNotEmpty ||
      namespace == MergeNamespaceOutcome.adoptionFailed;

  /// The same result with the identity outcome set.
  MergeResult withNamespace(MergeNamespaceOutcome outcome) => MergeResult(
    added: added,
    identical: identical,
    conflicts: conflicts,
    possibleDuplicates: possibleDuplicates,
    replaced: replaced,
    skippedRows: skippedRows,
    adjustments: adjustments,
    namespace: outcome,
  );
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
    this.skippedRows = const [],
    this.adjustments = const [],
  });

  /// The parsed incoming books (not yet applied).
  final List<Book> incomingBooks;

  /// Rows the parser rejected — forwarded into the apply's [MergeResult] so
  /// a Join/Overwrite still tells the user what the file lost (N07).
  final List<String> skippedRows;

  /// Parser adjustments to kept rows — forwarded like [skippedRows].
  final List<String> adjustments;

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
    // N07: the library identity is read/adopted through its single owner
    // (`SettingsController`), not the settings repository.
    required LibraryNamespace namespace,
    // N14: the concrete JSON codec lives in infrastructure; the use case
    // depends on the domain port and gets the implementation via DI.
    required LibraryJsonParser jsonParser,
    required CatalogueReplacementGuard replacementGuard,
  }) : _bookRepo = bookRepo,
       _namespace = namespace,
       _json = jsonParser,
       _replacementGuard = replacementGuard;

  final CatalogueReplacementGuard _replacementGuard;
  final BookRepository _bookRepo;
  final LibraryNamespace _namespace;
  final LibraryJsonParser _json;

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

    // M17: a failed ID read/mint must not be papered over with a blank ID —
    // that would route every file into the "differing IDs" decision path.
    final identity = await _namespace.current();
    if (identity.isLeft()) {
      return identity.match(left, (_) => throw StateError('unreachable'));
    }
    final local = identity.getOrElse((_) => throw StateError('unreachable'));
    final localLibraryId = local.id.trim();

    // ID gate (D40). Match → merge. Differ (or incoming has no ID) → decision.
    final idsMatch =
        incomingLibraryId.isNotEmpty && incomingLibraryId == localLibraryId;
    if (!idsMatch) {
      final localBooks = await _bookRepo.getAll();
      return localBooks.flatMap(
        (books) => right(
          MergeDiffersDecision(
            incomingBooks: payload.books,
            incomingLibraryId: incomingLibraryId,
            incomingLibraryName: incomingLibraryName,
            localLibraryName: local.name,
            localIsEmpty: books.isEmpty,
            skippedRows: payload.parseErrors,
            adjustments: payload.warnings,
          ),
        ),
      );
    }

    final merged = await _applyEngineMerge(
      payload.books,
      skippedRows: payload.parseErrors,
      adjustments: payload.warnings,
    );
    return merged.map(MergeMerged.new);
  }

  /// JOIN (D40, the non-destructive default for a differ-IDs file): union the
  /// incoming books via the engine, AND adopt the incoming library ID + name so
  /// the two devices share a namespace going forward. Nobody loses data.
  ///
  /// N07 order: books FIRST, identity SECOND. If the union fails, the left is
  /// returned and this device keeps its own ID (the decision stays valid —
  /// nothing changed). If the union lands and the identity write then fails,
  /// the result is still a right, with [MergeNamespaceOutcome.adoptionFailed]
  /// so the page can say exactly what did not happen.
  Future<Either<Failure, MergeResult>> applyJoin(
    MergeDiffersDecision decision,
  ) async {
    final merged = await _applyEngineMerge(
      decision.incomingBooks,
      skippedRows: decision.skippedRows,
      adjustments: decision.adjustments,
    );
    if (merged.isLeft()) return merged;
    final result = merged.getOrElse((_) => throw StateError('unreachable'));
    return right(result.withNamespace(await _adoptNamespace(decision)));
  }

  /// OVERWRITE (D40, the guarded secondary): replace the local catalogue with
  /// the incoming one and adopt its library ID + name. Destructive — intended
  /// for a fresh/empty install becoming a clean replica. The caller is
  /// responsible for an explicit confirm before invoking this.
  ///
  /// The delete+insert runs as ONE repository transaction
  /// ([BookRepository.replaceAll]): a failure mid-way (e.g. a UNIQUE violation
  /// on a crafted file) rolls back, so the device is never left with a
  /// partially-deleted catalogue (REVIEW_FINDINGS_2 S5).
  ///
  /// Returns a [MergeResult] with `replaced: true` and `added` = the number of
  /// books now on the device, so the page can describe a replacement as a
  /// replacement (N07) — not as a zero-count merge.
  Future<Either<Failure, MergeResult>> applyOverwrite(
    MergeDiffersDecision decision,
  ) => _replacementGuard.protectReplacement((scope) async {
    // The snapshot and replacement share a transaction, while the guard
    // prevents a vault write from changing the loan set between them (M03).
    final replaced = await _bookRepo.runInTransaction<int>(() async {
      var incoming = decision.incomingBooks
          .map((b) => b.copyWith(id: Book.emptyId))
          .toList();
      final loanIds = scope.retainedLoanBookIds;
      if (loanIds != null) {
        final local = await _bookRepo.getAll();
        if (local.isLeft()) return local.map((_) => 0);
        final plan = CatalogueReplacementPlan.build(
          local: local.getOrElse((_) => const []),
          incoming: incoming,
          loanBookIds: loanIds,
        );
        if (plan.isLeft()) return plan.map((_) => 0);
        incoming = plan.getOrElse((_) => const []);
      }
      if (!scope.isCurrent) return left(CatalogueReplacementScope.cancelled);
      // The repository reports how many rows it actually inserted — that is
      // the number the summary shows, not the file's row count.
      final result = await _bookRepo.replaceAll(incoming);
      if (!scope.isCurrent) return left(CatalogueReplacementScope.cancelled);
      return result;
    });
    if (replaced.isLeft()) {
      return replaced.match(left, (_) => throw StateError('unreachable'));
    }
    // The catalogue is already replaced. A failed identity adoption is NOT
    // an error for the whole operation any more (N07): the data is exactly
    // what the user asked for, so report the outcome and let the page say
    // "identity not adopted" — never silent, never a false failure either.
    return right(
      MergeResult(
        added: replaced.getOrElse((_) => 0),
        identical: 0,
        conflicts: const [],
        possibleDuplicates: const [],
        replaced: true,
        skippedRows: decision.skippedRows,
        adjustments: decision.adjustments,
        namespace: await _adoptNamespace(decision),
      ),
    );
  });

  /// Adopts the incoming identity through its owner AFTER the data landed.
  /// A file without an ID has nothing to adopt ([MergeNamespaceOutcome
  /// .unchanged]); a failed write is reported, not thrown, because the books
  /// are already on the device and the user must hear both facts.
  Future<MergeNamespaceOutcome> _adoptNamespace(
    MergeDiffersDecision decision,
  ) async {
    if (decision.incomingLibraryId.isEmpty) {
      return MergeNamespaceOutcome.unchanged;
    }
    final adopted = await _namespace.adopt(
      id: decision.incomingLibraryId,
      name: decision.incomingLibraryName,
    );
    return adopted.match(
      (_) => MergeNamespaceOutcome.adoptionFailed,
      (_) => MergeNamespaceOutcome.adopted,
    );
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
        // M09: "take theirs" takes their CATALOGUE fields. The cover is the
        // one exception — a photo of the physical book taken on this device
        // is kept; their cover lands only when there is no local cover.
        // `copyWith` cannot null a field, so a null resolution (both sides
        // blank) simply leaves the incoming null in place.
        final cover = resolveIncomingCover(
          existing: local.coverUrl,
          incoming: incoming.coverUrl,
        );
        final updated = await _bookRepo.update(
          incoming.copyWith(
            id: local.id,
            bookUid: local.bookUid,
            coverUrl: cover,
          ),
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
  ///
  /// The adds land via ONE [BookRepository.insertAll] call, which is atomic —
  /// the reported [MergeResult.added] can never disagree with the committed
  /// DB state (REVIEW_FINDINGS_2 S5: the old sequential loop committed rows
  /// 1..N and then reported total failure when row N+1 violated a UNIQUE
  /// index).
  Future<Either<Failure, MergeResult>> _applyEngineMerge(
    List<Book> incoming, {
    required List<String> skippedRows,
    required List<String> adjustments,
  }) async {
    final localRes = await _bookRepo.getAll();
    if (localRes.isLeft()) {
      return localRes.match(left, (_) => throw StateError('unreachable'));
    }
    final local = localRes.getOrElse((_) => const <Book>[]);
    final plan = planMerge(local, incoming);
    if (plan.toAdd.isNotEmpty) {
      final ins = await _bookRepo.insertAll(
        plan.toAdd.map((b) => b.copyWith(id: Book.emptyId)).toList(),
      );
      if (ins.isLeft()) {
        return ins.match(left, (_) => throw StateError('unreachable'));
      }
    }
    return right(
      MergeResult(
        added: plan.toAdd.length,
        identical: plan.identical,
        conflicts: plan.conflicts,
        possibleDuplicates: plan.possibleDuplicates,
        skippedRows: skippedRows,
        adjustments: adjustments,
      ),
    );
  }
}
