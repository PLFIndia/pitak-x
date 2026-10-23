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
/// Item kinds and periodicals (plan S19, ADR 0013 D6 / ADR 0014 W1): the plan
/// covers the file's `periodicals[]` alongside its `books[]` — series apply
/// FIRST (a union adds new titles, keeps matched local ones), then the item
/// union lands, then every merged series' issues are re-projected (an import
/// can leave them stale, S18; D3). All of it is ONE transaction, so a merge
/// is all-or-nothing.
///
/// Review finding N07 (a failed Join could still change this device's
/// library identity, and partial merges were reported as complete) — three
/// rules every apply path follows:
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
import 'package:pitaka/features/import_export/application/merge_planner.dart';
import 'package:pitaka/features/import_export/application/merge_result.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_plan.dart';
import 'package:pitaka/features/library/domain/cover_precedence.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/library_id.dart';
import 'package:pitaka/features/periodicals/application/issue_reprojection.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';

export 'package:pitaka/features/import_export/application/merge_result.dart';

/// Reconciles an incoming Pitaka-JSON library file with the local catalogue.
final class MergeLibraryUseCase {
  /// Creates the use case over its collaborators.
  MergeLibraryUseCase({
    required CatalogueItemRepository bookRepo,
    // ADR 0014 W1: schema v4 payloads carry periodicals; the merge plans and
    // applies them before the item rows so issues meet their series in
    // place. Required on purpose — an optional store would let a merge
    // silently drop a v4 file's series (the pre-S19 bug).
    required PeriodicalRepository periodicalRepo,
    // N07: the library identity is read/adopted through its single owner
    // (`SettingsController`), not the settings repository.
    required LibraryNamespace namespace,
    // N14: the concrete JSON codec lives in infrastructure; the use case
    // depends on the domain port and gets the implementation via DI.
    required LibraryJsonParser jsonParser,
    required CatalogueReplacementGuard replacementGuard,
    // N10-c: where the (CPU-heavy) plan is computed. Production injects the
    // worker-isolate planner from infrastructure (N14: application code
    // never touches `dart:isolate`); tests inject a synchronous or recording
    // one. Required on purpose — a silently synchronous default would put the
    // plan back on the UI isolate the moment someone forgot to wire it.
    required MergePlanner planner,
  }) : _bookRepo = bookRepo,
       _periodicalRepo = periodicalRepo,
       _namespace = namespace,
       _json = jsonParser,
       _replacementGuard = replacementGuard,
       _planner = planner,
       _reprojection = IssueReprojection(
         periodicals: periodicalRepo,
         items: bookRepo,
       );

  final CatalogueReplacementGuard _replacementGuard;
  final MergePlanner _planner;
  final CatalogueItemRepository _bookRepo;
  final PeriodicalRepository _periodicalRepo;
  final LibraryNamespace _namespace;
  final LibraryJsonParser _json;

  /// The shared re-projection loop for merged series (D3).
  final IssueReprojection _reprojection;

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
    // A file with nothing mergeable (merge never applies wishlist rows) and
    // only parse errors is a hard failure; a periodicals-only v4 file is a
    // valid merge input.
    if (payload.items.isEmpty &&
        payload.periodicals.isEmpty &&
        payload.parseErrors.isNotEmpty) {
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
      if (localBooks.isLeft()) {
        return localBooks.match(left, (_) => throw StateError('unreachable'));
      }
      // "Empty" must see the whole library — an overwrite also replaces the
      // magazine titles, so a titles-only library is NOT empty.
      final localSeries = await _periodicalRepo.listAll();
      if (localSeries.isLeft()) {
        return localSeries.match(left, (_) => throw StateError('unreachable'));
      }
      return right(
        MergeDiffersDecision(
          incomingBooks: payload.items,
          incomingPeriodicals: payload.periodicals,
          incomingLibraryId: incomingLibraryId,
          incomingLibraryName: incomingLibraryName,
          localLibraryName: local.name,
          localIsEmpty:
              localBooks.getOrElse((_) => const []).isEmpty &&
              localSeries.getOrElse((_) => const []).isEmpty,
          skippedRows: payload.parseErrors,
          adjustments: payload.warnings,
        ),
      );
    }

    final merged = await _applyEngineMerge(
      payload.items,
      payload.periodicals,
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
      decision.incomingPeriodicals,
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
  /// The periodical replacement + book delete+insert run as ONE repository
  /// transaction ([CatalogueItemRepository.replaceAll]): a failure mid-way
  /// (e.g. a UNIQUE violation on a crafted file) rolls back, so the device is
  /// never left with a partially-deleted catalogue (REVIEW_FINDINGS_2 S5).
  /// Series go first (W1 order); loans never reference a series (F2), so the
  /// periodical replacement is unconditional inside the guard.
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
      // W1: periodicals first — the incoming issues point at the incoming
      // series uids, so the series rows must land in the same transaction.
      final series = await _periodicalRepo.replaceAll(
        decision.incomingPeriodicals
            .map((p) => p.copyWith(id: Periodical.emptyId))
            .toList(),
      );
      if (series.isLeft()) {
        return series.match(left, (_) => throw StateError('unreachable'));
      }
      var incoming = decision.incomingBooks
          .map((b) => b.copyWith(id: CatalogueItem.emptyId))
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
        periodicalsAdded: decision.incomingPeriodicals.length,
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
  ///    (preserve local id + itemUid so identity is stable; take the incoming
  ///    catalogue fields).
  ///  - keep-both   → insert the incoming as a NEW separate
  ///    book with a FRESH identity (null uid so the mapper mints one; dropped
  ///    ISBN since it is unique and still held by the original row — D2: two
  ///    rows never share one ISBN). The KIND is kept (`details` travels): a
  ///    keep-both must never silently turn an issue into a book — if its D6
  ///    key then collides with the original row, the repository answers
  ///    [DuplicateIssueFailure] and the review row shows it (fail closed).
  ///
  /// N07 guards (this is a catalogue ingress like any other):
  ///  - take-theirs is REFUSED when [local] was never persisted
  ///    (`id == CatalogueItem.emptyId`). That is the in-file key-collision
  ///    shape — `PossibleDuplicate.local` is then the earlier row from the SAME
  ///    file, not a book on this device — so there is no row to overwrite.
  ///    Before, this reached the repository and came back as a misleading "not
  ///    found". The page hides the button too; this is the belt.
  ///  - take-theirs is REFUSED when the two sides are different KINDS (D6/D8:
  ///    an item cannot change its kind after creation — overwriting in place
  ///    would flip it). The page hides the button too.
  ///  - both writing branches pass the built book through
  ///    [CatalogueItem.validate] (M15, same as `UpdateCatalogueItemUseCase`):
  ///    the incoming rows were validated by the parser, but the row written
  ///    here is BUILT from them, and the gate belongs right before the write.
  ///    The normalised book is what lands (a disallowed cover ref is dropped,
  ///    not rejected).
  Future<Either<Failure, Unit>> applyResolution({
    required CatalogueItem local,
    required CatalogueItem incoming,
    required MergeResolution resolution,
  }) async {
    switch (resolution) {
      case MergeResolution.keepMine:
        return right(unit);
      case MergeResolution.takeTheirs:
        if (local.id == CatalogueItem.emptyId) {
          return left(
            const ValidationFailure(
              'Both of these rows come from the same file, so there is no '
              'book on this device to replace. Skip it or add it as a '
              'separate book.',
            ),
          );
        }
        if (local.kind != incoming.kind) {
          return left(
            const ValidationFailure(
              'This item cannot change its kind after it was added. Keep '
              'yours, or add theirs as a separate entry.',
            ),
          );
        }
        // M09: "take theirs" takes their CATALOGUE fields. The cover is the
        // one exception — a photo of the physical book taken on this device
        // is kept; their cover lands only when there is no local cover.
        // `copyWith` cannot null a field, so a null resolution (both sides
        // blank) simply leaves the incoming null in place.
        final cover = resolveIncomingCover(
          existing: local.coverUrl,
          incoming: incoming.coverUrl,
        );
        return _validated(
          incoming.copyWith(
            id: local.id,
            itemUid: local.itemUid,
            coverUrl: cover,
          ),
        ).match(
          (failure) async => left(failure),
          (book) async => (await _bookRepo.update(book)).map((_) => unit),
        );
      case MergeResolution.keepBoth:
        // copyWith cannot null a field (it uses `??`), and a true "keep both"
        // MUST drop the incoming uid + ISBN (both UNIQUE columns still held by
        // the original row) or the duplicate would collide. Build it fresh.
        return _validated(_freshCopyOf(incoming)).match(
          (failure) async => left(failure),
          (book) async => (await _bookRepo.insert(book)).map((_) => unit),
        );
    }
  }

  /// The M15 gate as a typed failure (first field error, user wording).
  static Either<Failure, CatalogueItem> _validated(CatalogueItem book) =>
      CatalogueItem.validate(
        book,
      ).mapLeft((errors) => ValidationFailure(errors.first.userMessage));

  /// A separate-entry copy of [b] with a CLEARED cross-device identity: no uid
  /// (the repo mints one), no ISBN (unique, still held by the original row),
  /// and an unset id (a brand-new row). Keeps every catalogue field — and the
  /// KIND (`details`, D8): a keep-both of an issue stays an issue of the same
  /// (winning) series; a key collision with the original row then fails the
  /// insert with [DuplicateIssueFailure] instead of silently flipping kinds.
  static CatalogueItem _freshCopyOf(CatalogueItem b) => CatalogueItem(
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
    details: b.details,
  );

  /// Runs the engine against the current library and auto-applies the add-only
  /// union (the new rows get fresh ids but KEEP their uid so future merges
  /// reconcile). Conflicts + possible-duplicates are returned, not applied.
  ///
  /// The whole apply — new series first (W1), then the new items, then the
  /// re-projection of every merged series' issues (D3; repairs the stale
  /// projections an import can leave behind, S18) — lands in ONE transaction
  /// (REVIEW_FINDINGS_2 S5: the old sequential loop committed rows 1..N and
  /// then reported total failure when row N+1 violated a UNIQUE index). The
  /// reported [MergeResult.added] can never disagree with the committed DB
  /// state.
  Future<Either<Failure, MergeResult>> _applyEngineMerge(
    List<CatalogueItem> incoming,
    List<Periodical> incomingPeriodicals, {
    required List<String> skippedRows,
    required List<String> adjustments,
  }) async {
    final localRes = await _bookRepo.getAll();
    if (localRes.isLeft()) {
      return localRes.match(left, (_) => throw StateError('unreachable'));
    }
    final local = localRes.getOrElse((_) => const <CatalogueItem>[]);
    final seriesRes = await _periodicalRepo.listAll();
    if (seriesRes.isLeft()) {
      return seriesRes.match(left, (_) => throw StateError('unreachable'));
    }
    final localPeriodicals = [
      for (final summary in seriesRes.getOrElse((_) => const []))
        summary.periodical,
    ];
    final plan = await _planner(
      local,
      incoming,
      localPeriodicals,
      incomingPeriodicals,
    );
    final applied = await _bookRepo.runInTransaction(() async {
      // W1: series FIRST — the incoming issues were re-anchored to the
      // winning series by the planner, so the series rows land before (and
      // together with) any issue that points at them.
      if (plan.periodicalsToAdd.isNotEmpty) {
        final ins = await _periodicalRepo.insertAll(
          plan.periodicalsToAdd
              .map((p) => p.copyWith(id: Periodical.emptyId))
              .toList(),
        );
        if (ins.isLeft()) return ins.map((_) => 0);
      }
      if (plan.toAdd.isNotEmpty) {
        final ins = await _bookRepo.insertAll(
          plan.toAdd.map((b) => b.copyWith(id: CatalogueItem.emptyId)).toList(),
        );
        if (ins.isLeft()) return ins.map((_) => 0);
      }
      // D3: issues of merged series are re-projected from the stored series
      // (skip-unchanged inside, so up-to-date rows are not rewritten).
      for (final series in plan.matchedLocalSeries) {
        final reproj = await _reprojection.call(series);
        if (reproj.isLeft()) return reproj.map((_) => 0);
      }
      return right(plan.toAdd.length);
    });
    if (applied.isLeft()) {
      return applied.match(left, (_) => throw StateError('unreachable'));
    }
    return right(
      MergeResult(
        added: plan.toAdd.length,
        identical: plan.identical,
        conflicts: plan.conflicts,
        possibleDuplicates: plan.possibleDuplicates,
        skippedRows: skippedRows,
        adjustments: adjustments,
        periodicalsAdded: plan.periodicalsToAdd.length,
        periodicalsIdentical: plan.periodicalsIdentical,
        periodicalConflicts: plan.periodicalConflicts,
      ),
    );
  }
}
