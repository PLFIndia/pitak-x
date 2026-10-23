/// Pure, side-effect-free engine for the multi-maintainer library merge
/// (PLAN-merge.md). Faithful Dart port of Kotlin
/// `dev.khoj.pitaka.domain.merge.LibraryMergeEngine`, extended in plan S19
/// for item kinds and periodicals (ADR 0013 D6).
///
/// Given the LOCAL library and an INCOMING library (parsed from another
/// maintainer's exported file), it produces a [MergePlan] the caller applies.
/// No Flutter, no IO, no repository — exhaustively unit-testable (AGENTS.md
/// §3.1).
///
/// Semantics (locked decisions, PLAN-merge.md):
///  - **add-only + manual conflict surfacing.** Union the catalogues; auto-add
///    incoming books the local device doesn't have; NEVER silently overwrite an
///    existing book. When the same book differs, surface it for the user.
///  - **identity, evaluated in order:**
///      1. `itemUid` — the stable cross-device id. Same uid ⇒ same book.
///      2. `isbn` — for books with no uid match. Same ISBN ⇒ same physical book
///         (independently scanned on two phones reconciles here).
///      3. no uid, no isbn ⇒ fall to fuzzy.
///  - **issue identity (ADR 0013 D6):** an issue's chain is `itemUid` → its
///    D6 key (numbered `(periodicalUid, volume ?? 0, issueNumber)` / bound
///    `(periodicalUid, issueDate, boundUntil)`, see `issue_identity.dart`) →
///    fuzzy title among keyless issues of the SAME series. A same-uid row
///    whose kind differs is a CONFLICT, never an update (D8).
///  - **periodicals merge FIRST** (uid → ISSN → exact title; add-only,
///    removal-as-conflict — see `periodical_merge.dart`): incoming issues are
///    re-anchored to the winning series and re-projected from it BEFORE the
///    item pass, so a series rename never storms per-issue conflicts (D.2).
///  - **no-ISBN fuzzy (Q-NOISBN = B):** a no-ISBN incoming book with no exact
///    match is compared by normalised title+author to local no-ISBN books of
///    the SAME KIND. A close match is surfaced as a POSSIBLE DUPLICATE for
///    the user to confirm — never auto-merged (that would be guessing),
///    never silently added either.
///  - **soft-delete is just a field.** A `removed`-flag difference between two
///    matched books is surfaced like any other conflict (never applied silently
///    in either direction).
///
/// What is automatic vs surfaced:
///  - [MergePlan.toAdd]     — incoming books with NO local match. Auto-applied.
///  - [MergePlan.identical] — matched + field-equal. No-op (counted only).
///  - [MergePlan.conflicts] — matched but differing. User resolves (row-level).
///  - [MergePlan.possibleDuplicates] — no-ISBN fuzzy misses AND in-file
///    identity-key collisions (two incoming rows sharing a uid/ISBN/issue key
///    can never both insert). User confirms.
///  - [MergePlan.periodicalsToAdd] / [MergePlan.periodicalConflicts] — the
///    series side (add-only; conflicts keep the local row).
///
/// Each incoming book matches AT MOST one local book, and two incoming books
/// never match the same local book (first-claim wins, so a messy incoming file
/// can't fan-in onto one local row).
///
/// Cost (N10-b): the fuzzy pass tokenises each local candidate ONCE per pool
/// and looks candidates up through an inverted index (token → candidates), so
/// an incoming row is scored only against candidates that share at least one
/// token with it (see `fuzzy_index.dart`).
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/fuzzy_index.dart';
import 'package:pitaka/features/library/domain/merge/issue_identity.dart';
import 'package:pitaka/features/library/domain/merge/merge_fields.dart';
import 'package:pitaka/features/library/domain/merge/periodical_merge.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';

export 'package:pitaka/features/library/domain/merge/merge_fields.dart';
export 'package:pitaka/features/library/domain/merge/periodical_merge.dart';

/// How an incoming book was matched to a local book (for UI explanation).
enum MatchKind {
  /// Matched by the stable cross-device `itemUid`.
  uid,

  /// Matched by normalised ISBN.
  isbn,

  /// Matched by the D6 issue identity key (numbered/bound, see
  /// `issue_identity.dart`).
  issueIdentity,
}

/// An incoming book that matched a local book by uid or ISBN but whose
/// publishable fields differ. Carries both sides so the UI can show a diff and
/// offer row-level resolution (keep local / take incoming / keep both).
class MergeConflict {
  /// Creates a conflict pair.
  const MergeConflict({
    required this.local,
    required this.incoming,
    required this.matchedBy,
  });

  /// The local book.
  final CatalogueItem local;

  /// The incoming book that matched it.
  final CatalogueItem incoming;

  /// What established the match.
  final MatchKind matchedBy;

  /// True when the only difference is the soft-delete state.
  bool get isRemovalOnly => mergeEquals(
    local.copyWith(removed: incoming.removed, removedAt: incoming.removedAt),
    incoming,
  );
}

/// Why an incoming row was surfaced as a [PossibleDuplicate] (N07). The UI
/// needs this to explain the row and to offer the right actions — the score
/// alone cannot tell the two apart, because a fuzzy hit with identical
/// title+author tokens also scores exactly 1.0.
enum DuplicateReason {
  /// A no-ISBN incoming book whose normalised title+author resembles a local
  /// no-ISBN book ([PossibleDuplicate.similarity] is the Jaccard score).
  similarTitle,

  /// The incoming row's uid/ISBN/issue key is already held by another row (a
  /// claimed local row, or an earlier row from the same file), so it can
  /// never be inserted as-is (UNIQUE indexes).
  identityKey,
}

/// An incoming book that resembles a book already on the winning side of the
/// merge but is not an exact match. Surfaced for the user to either merge
/// (same book) or add separately. Two shapes, told apart by [reason]:
///  - **fuzzy** ([DuplicateReason.similarTitle]): a no-ISBN incoming book
///    resembling a local no-ISBN book; [similarity] is the token-set Jaccard
///    score in (0,1].
///  - **identity-key collision** ([DuplicateReason.identityKey]): the
///    incoming row's uid/ISBN/issue key is already held by a claimed local
///    row or an earlier incoming row from the SAME file, so inserting it
///    would violate the UNIQUE indexes; [similarity] is 1.0 and [local] is
///    whichever row holds the key (for an in-file collision that is the
///    earlier INCOMING row — `id == CatalogueItem.emptyId`, not a persisted
///    local book, so "take theirs" has no row to overwrite).
class PossibleDuplicate {
  /// Creates a possible-duplicate pair.
  const PossibleDuplicate({
    required this.local,
    required this.incoming,
    required this.similarity,
    this.reason = DuplicateReason.similarTitle,
  });

  /// The book already on the winning side (a local row, or — for an in-file
  /// key collision — the earlier incoming row already queued to add).
  final CatalogueItem local;

  /// The incoming book resembling it.
  final CatalogueItem incoming;

  /// Token-set Jaccard similarity in (0,1]; exactly 1.0 for an identity-key
  /// collision.
  final double similarity;

  /// Why this pair was surfaced.
  final DuplicateReason reason;
}

/// The result of [planMerge]: what to auto-add and what to surface.
class MergePlan {
  /// Creates a merge plan.
  const MergePlan({
    required this.toAdd,
    required this.conflicts,
    required this.possibleDuplicates,
    required this.identical,
    this.periodicalsToAdd = const [],
    this.periodicalConflicts = const [],
    this.periodicalsIdentical = 0,
    this.matchedLocalSeries = const [],
  });

  /// Incoming books with NO local match — applied automatically.
  final List<CatalogueItem> toAdd;

  /// Matched but differing — await user resolution.
  final List<MergeConflict> conflicts;

  /// Fuzzy near-misses and in-file identity-key collisions — await user
  /// confirmation.
  final List<PossibleDuplicate> possibleDuplicates;

  /// Matched + field-equal; no action taken (counted only).
  final int identical;

  /// Incoming periodicals with no local match — applied automatically BEFORE
  /// the items (ADR 0014 W1 order).
  final List<Periodical> periodicalsToAdd;

  /// Periodicals matched but differing — the local row is kept (merge is
  /// add-only for series); reported, never applied silently.
  final List<PeriodicalMergeConflict> periodicalConflicts;

  /// Periodicals matched + field-equal; no action taken (counted only).
  final int periodicalsIdentical;

  /// The distinct LOCAL periodicals that won a match. The use case
  /// re-projects their issues after applying: an import can leave a series'
  /// stored issues stale (S18 updates the series row only), and the merge is
  /// the seam that repairs them (D3).
  final List<Periodical> matchedLocalSeries;

  /// True when there is anything for the user to review. Periodical
  /// conflicts are NOT review items — they are informational (the local
  /// series was kept); there is no per-row resolution for them.
  bool get hasReviewItems =>
      conflicts.isNotEmpty || possibleDuplicates.isNotEmpty;

  /// True when the merge changes nothing.
  bool get isNoOp =>
      toAdd.isEmpty &&
      conflicts.isEmpty &&
      possibleDuplicates.isEmpty &&
      periodicalsToAdd.isEmpty &&
      periodicalConflicts.isEmpty;
}

/// Plans a merge of [incoming] into [local]. Pure: no IO, no mutation.
///
/// [localPeriodicals] / [incomingPeriodicals] are the series of each side
/// (schema v4 files carry them top-level; ADR 0014 W1). They default to
/// empty so a books-only call (a v3 file, a test) behaves exactly as before
/// kinds existed. [tokenizer] is a test seam (see [Tokenizer]); leave it at
/// the default.
MergePlan planMerge(
  List<CatalogueItem> local,
  List<CatalogueItem> incoming, {
  List<Periodical> localPeriodicals = const [],
  List<Periodical> incomingPeriodicals = const [],
  double fuzzyThreshold = kDefaultFuzzyThreshold,
  Tokenizer tokenizer = tokenSet,
}) {
  // Periodicals merge FIRST (risk table D.2): the winners decide which
  // series each incoming issue attaches to and what its projected fields
  // say, so the item pass below compares canonical rows.
  final periodicalPlan = planPeriodicalMerge(
    localPeriodicals,
    incomingPeriodicals,
  );
  final localSeriesByUid = <String, Periodical>{
    for (final p in localPeriodicals)
      if (p.periodicalUid != null && p.periodicalUid!.trim().isNotEmpty)
        p.periodicalUid!.trim(): p,
  };

  // D3/D6: incoming issues plan in their CANONICAL form — re-anchored to
  // the winning series and re-projected from it. An issue no series claims
  // degrades to a plain book (the importer's W1 orphan rule, repeated here
  // so a hand-built payload can never plan a dangling series link).
  final reattached = [
    for (final item in incoming)
      reattachIncomingIssue(item, periodicalPlan.winners, localSeriesByUid),
  ];

  // Local issues of a MERGED series compare by their canonical projection
  // too: an import can leave the stored rows stale (S18 updates the series
  // without re-projecting), and a stale projected title must not read as a
  // per-issue conflict storm (D.2). The use case repairs the stored rows
  // after applying (MergePlan.matchedLocalSeries).
  final mergedLocalUids = {
    for (final p in periodicalPlan.matchedLocalSeries) p.periodicalUid,
  };
  final localNormalised = [
    for (final item in local)
      item.issue != null && mergedLocalUids.contains(item.issue!.periodicalUid)
          ? IssueProjection.apply(
              item,
              localSeriesByUid[item.issue!.periodicalUid]!,
            )
          : item,
  ];

  // Indexes for O(1) exact matching. Blank keys are ignored.
  final localByUid = <String, CatalogueItem>{};
  final localByIsbn = <String, CatalogueItem>{};
  final localByIssueKey = <IssueIdentityKey, CatalogueItem>{};
  final keylessIssuesBySeries = <String, List<CatalogueItem>>{};
  for (final b in localNormalised) {
    final uid = b.itemUid?.trim();
    if (uid != null && uid.isNotEmpty) {
      localByUid.putIfAbsent(uid, () => b);
    }
    final isbn = normIsbn(b.isbn);
    if (isbn.isNotEmpty) {
      localByIsbn.putIfAbsent(isbn, () => b);
    }
    final issue = b.issue;
    if (issue != null) {
      final key = issueIdentityKey(issue);
      if (key != null) {
        localByIssueKey.putIfAbsent(key, () => b);
      } else {
        // Keyless (date-only) issues are the series-scoped fuzzy pool (D6).
        keylessIssuesBySeries
            .putIfAbsent(issue.periodicalUid.trim(), () => [])
            .add(b);
      }
    }
  }

  // Fuzzy candidate pools, one per KIND so a book never fuzzy-matches an
  // issue or an "other" (D6/O4). The indexes are lazy: a file whose rows all
  // carry identity keys never tokenises anything.
  final bookIndex = FuzzyIndex(
    localNormalised
        .where((b) => b.details == null && normIsbn(b.isbn).isEmpty)
        .toList(),
    tokenizer,
  );
  final otherIndex = FuzzyIndex(
    localNormalised
        .where((b) => b.details is OtherItemOf && normIsbn(b.isbn).isEmpty)
        .toList(),
    tokenizer,
  );
  final issueIndexes = <String, FuzzyIndex>{};

  final toAdd = <CatalogueItem>[];
  final conflicts = <MergeConflict>[];
  final possibleDuplicates = <PossibleDuplicate>[];
  var identical = 0;

  // A local row may be claimed by at most one incoming book (no fan-in).
  final claimedLocalIds = <int>{};

  // Identity keys already spoken for by rows routed to [toAdd] FROM THIS
  // FILE. The DB enforces UNIQUE on book_uid and isbn (and on the D6 issue
  // keys), so a second incoming row reusing any key can never be inserted —
  // it must be surfaced for review instead of added (REVIEW_FINDINGS_2 S5:
  // two rows in one file sharing an ISBN otherwise both landed in toAdd and
  // the second insert failed mid-apply, leaving a partial union misreported
  // as total failure).
  final addedByUid = <String, CatalogueItem>{};
  final addedByIsbn = <String, CatalogueItem>{};
  final addedByIssueKey = <IssueIdentityKey, CatalogueItem>{};

  void routeToAdd(CatalogueItem b) {
    toAdd.add(b);
    final uid = b.itemUid?.trim();
    if (uid != null && uid.isNotEmpty) addedByUid[uid] = b;
    final isbn = normIsbn(b.isbn);
    if (isbn.isNotEmpty) addedByIsbn[isbn] = b;
    final issue = b.issue;
    if (issue != null) {
      final key = issueIdentityKey(issue);
      if (key != null) addedByIssueKey[key] = b;
    }
  }

  for (final inc in reattached) {
    final incUid = inc.itemUid?.trim();
    final incIsbn = normIsbn(inc.isbn);
    final incIssue = inc.issue;
    final incIssueKey = incIssue == null ? null : issueIdentityKey(incIssue);

    // 1) uid match.
    final byUid = (incUid != null && incUid.isNotEmpty)
        ? localByUid[incUid]
        : null;
    if (byUid != null && !claimedLocalIds.contains(byUid.id)) {
      claimedLocalIds.add(byUid.id);
      // mergeEquals compares the kind too (MergeField.kind): a same-uid row
      // whose kind differs is a CONFLICT (D6), never an update — an item
      // cannot change its kind after creation (D8).
      if (mergeEquals(byUid, inc)) {
        identical++;
      } else {
        conflicts.add(
          MergeConflict(local: byUid, incoming: inc, matchedBy: MatchKind.uid),
        );
      }
      continue;
    }

    // 2) Issue-identity match (D6) — the issue's own key precedes ISBN.
    final byIssueKey = incIssueKey == null
        ? null
        : localByIssueKey[incIssueKey];
    if (byIssueKey != null && !claimedLocalIds.contains(byIssueKey.id)) {
      claimedLocalIds.add(byIssueKey.id);
      if (mergeEquals(byIssueKey, inc)) {
        identical++;
      } else {
        conflicts.add(
          MergeConflict(
            local: byIssueKey,
            incoming: inc,
            matchedBy: MatchKind.issueIdentity,
          ),
        );
      }
      continue;
    }

    // 3) ISBN match.
    final byIsbn = incIsbn.isNotEmpty ? localByIsbn[incIsbn] : null;
    if (byIsbn != null && !claimedLocalIds.contains(byIsbn.id)) {
      claimedLocalIds.add(byIsbn.id);
      if (mergeEquals(byIsbn, inc)) {
        identical++;
      } else {
        conflicts.add(
          MergeConflict(
            local: byIsbn,
            incoming: inc,
            matchedBy: MatchKind.isbn,
          ),
        );
      }
      continue;
    }

    // 4) No UNCLAIMED local match. If any identity key is already held —
    //    by a local row an earlier incoming row claimed, or by an earlier
    //    incoming row already queued to add — this row can never be inserted
    //    (UNIQUE uid/isbn/issue keys). Surface it as a possible duplicate of
    //    the key holder (exact-identity near-miss, similarity 1.0) instead
    //    of adding.
    final keyHolder =
        byUid ??
        byIssueKey ??
        byIsbn ??
        (incUid != null && incUid.isNotEmpty ? addedByUid[incUid] : null) ??
        (incIssueKey == null ? null : addedByIssueKey[incIssueKey]) ??
        (incIsbn.isNotEmpty ? addedByIsbn[incIsbn] : null);
    if (keyHolder != null) {
      possibleDuplicates.add(
        PossibleDuplicate(
          local: keyHolder,
          incoming: inc,
          similarity: 1,
          reason: DuplicateReason.identityKey,
        ),
      );
      continue;
    }

    // 5) No exact match and no key collision. A row WITH an identity key
    //    (ISBN, or a D6 issue key) is genuinely new here → add it. With no
    //    key, try a fuzzy pass against the same-kind local pool (for an
    //    issue: the keyless issues of its own series).
    if (incIsbn.isNotEmpty || incIssueKey != null) {
      routeToAdd(inc);
      continue;
    }

    final pool = switch (inc.details) {
      null => bookIndex,
      OtherItemOf() => otherIndex,
      IssueOf(:final periodicalUid) => issueIndexes.putIfAbsent(
        periodicalUid.trim(),
        () => FuzzyIndex(
          keylessIssuesBySeries[periodicalUid.trim()] ?? const [],
          tokenizer,
        ),
      ),
    };
    final candidate = pool.best(
      tokenizer(inc),
      claimedLocalIds,
      fuzzyThreshold,
    );
    if (candidate != null) {
      claimedLocalIds.add(candidate.book.id);
      possibleDuplicates.add(
        PossibleDuplicate(
          local: candidate.book,
          incoming: inc,
          similarity: candidate.score,
        ),
      );
    } else {
      routeToAdd(inc);
    }
  }

  return MergePlan(
    toAdd: toAdd,
    conflicts: conflicts,
    possibleDuplicates: possibleDuplicates,
    identical: identical,
    periodicalsToAdd: periodicalPlan.toAdd,
    periodicalConflicts: periodicalPlan.conflicts,
    periodicalsIdentical: periodicalPlan.identical,
    matchedLocalSeries: periodicalPlan.matchedLocalSeries,
  );
}
