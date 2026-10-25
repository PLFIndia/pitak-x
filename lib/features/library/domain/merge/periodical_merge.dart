/// The periodical side of the multi-maintainer merge (library domain, pure
/// Dart; plan S19; ADR 0013 D2/D6/D8).
///
/// Runs INSIDE `planMerge`, before the item pass, because the periodical
/// outcome decides what the item pass sees (risk table D.2: "periodicals
/// merge first; issues re-projected after apply"):
///  1. every incoming issue is re-attached to the WINNING series
///     ([PeriodicalMergePlan.winners]) — remapped uid, fields re-projected
///     from the winner — so a series that matched under a different uid
///     (ISSN / exact title) never strands its issues, and a renamed series
///     never storms per-issue title conflicts;
///  2. the item engine then matches those normalised rows by the D6 chain
///     (`itemUid` → issue identity key → fuzzy title).
///
/// Merge is ADD-ONLY for series: a matched local periodical is never
/// overwritten by the file (unlike import, which updates in place). Any
/// difference — including a soft-delete flag, so a removal is never applied
/// silently in either direction — is surfaced as a [PeriodicalMergeConflict]
/// and the local row stays as it is.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/language_name.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';

/// How an incoming periodical was matched to a local one (for UI
/// explanation), mirroring the item engine's `MatchKind`.
enum PeriodicalMatchKind {
  /// Matched by the stable cross-device `periodicalUid`.
  uid,

  /// Matched by canonical ISSN (the same title tracked under two uids
  /// reconciles here, D7).
  issn,

  /// Matched by the exact (trimmed) title — the last resort when at least
  /// one side lacks a canonical ISSN. Different canonical ISSNs never match
  /// here: they identify different series even when their titles are equal.
  title,
}

/// An incoming periodical that matched a local one but differs from it.
/// Carries both sides so the UI can say WHAT was kept; [local] is the
/// winning side — a persisted local row, or (for an in-file key collision)
/// the earlier incoming row already queued to add, which has
/// `id == Periodical.emptyId`.
class PeriodicalMergeConflict {
  /// Creates a conflict pair.
  const PeriodicalMergeConflict({
    required this.local,
    required this.incoming,
    required this.matchedBy,
  });

  /// The periodical that stays (the local row wins every match: add-only).
  final Periodical local;

  /// The incoming periodical that was NOT added.
  final Periodical incoming;

  /// What established the match.
  final PeriodicalMatchKind matchedBy;
}

/// The result of [planPeriodicalMerge]: what to auto-add, what to surface,
/// and where each incoming series' issues belong.
class PeriodicalMergePlan {
  /// Creates a periodical merge plan.
  const PeriodicalMergePlan({
    required this.toAdd,
    required this.conflicts,
    required this.identical,
    required this.winners,
    required this.matchedLocalSeries,
  });

  /// An empty plan: no series anywhere.
  static const empty = PeriodicalMergePlan(
    toAdd: [],
    conflicts: [],
    identical: 0,
    winners: {},
    matchedLocalSeries: [],
  );

  /// Incoming periodicals with NO local match — applied automatically
  /// (their uids are kept; a blank uid is minted at insert).
  final List<Periodical> toAdd;

  /// Matched but differing (including in-file key collisions) — the local
  /// side is kept; surfaced so the merge page can say so.
  final List<PeriodicalMergeConflict> conflicts;

  /// Matched + field-equal; no action taken (counted only).
  final int identical;

  /// incoming `periodicalUid` → the series that uid's issues attach to: the
  /// matched LOCAL row for a uid/ISSN/title match (issues re-anchor to the
  /// local uid), or the incoming row itself when it is being added. Every
  /// incoming series with a non-blank uid has an entry — a series the item
  /// pass can always resolve.
  final Map<String, Periodical> winners;

  /// The distinct LOCAL periodicals that won a match (identical or
  /// conflicted). The use case re-projects their issues after applying
  /// (S18's import updates a series without re-projecting; the merge is the
  /// seam that repairs the stale projected fields, D3).
  final List<Periodical> matchedLocalSeries;

  /// True when the plan changes nothing about periodicals.
  bool get isNoOp => toAdd.isEmpty && conflicts.isEmpty;
}

/// Plans the periodical merge of [incoming] into [local]. Pure: no IO, no
/// mutation. Identity, in order (D6 mirrors uid → ISBN → title for series):
/// `periodicalUid` → canonical ISSN → exact title. First-claim wins: a local
/// row is matched by at most one incoming row (no fan-in). Title fallback is
/// suppressed when both rows have canonical ISSNs and those ISSNs differ:
/// an ISSN identifies the series, so equal display titles cannot override it.
///
/// A second incoming row whose uid/ISSN is already spoken for (by a claimed
/// local row or an earlier row of the SAME file) can never insert — the DB
/// enforces UNIQUE on both — so it is surfaced as a conflict with the key
/// holder instead of added (the item engine's identity-key rule, one level
/// up). Title does not dedupe rows WITHIN one file: two same-title rows
/// without uids/ISSNs are genuinely two series to add.
PeriodicalMergePlan planPeriodicalMerge(
  List<Periodical> local,
  List<Periodical> incoming,
) {
  // Indexes for O(1) exact matching. Blank keys are ignored; ISSNs compare
  // in canonical form (both sides are canonical by construction — the write
  // gate normalises — but a defensive normalise keeps a hand-built row from
  // slipping past the UNIQUE index's notion of equality).
  final localByUid = <String, Periodical>{};
  final localByIssn = <String, Periodical>{};
  final localByTitle = <String, Periodical>{};
  for (final p in local) {
    final uid = p.periodicalUid?.trim();
    if (uid != null && uid.isNotEmpty) localByUid.putIfAbsent(uid, () => p);
    final issn = Issn.normalize(p.issn);
    if (issn != null) localByIssn.putIfAbsent(issn, () => p);
    final title = p.title.trim();
    if (title.isNotEmpty) localByTitle.putIfAbsent(title, () => p);
  }

  final toAdd = <Periodical>[];
  final conflicts = <PeriodicalMergeConflict>[];
  var identical = 0;
  final winners = <String, Periodical>{};
  final matchedLocalSeries = <Periodical>[];
  final claimedLocalIds = <int>{};

  // Identity keys already spoken for by rows routed to [toAdd] FROM THIS
  // FILE (the item engine's addedByUid/addedByIsbn rule, for series).
  final addedByUid = <String, Periodical>{};
  final addedByIssn = <String, Periodical>{};

  for (final inc in incoming) {
    final uid = inc.periodicalUid?.trim();
    final hasUid = uid != null && uid.isNotEmpty;
    final issn = Issn.normalize(inc.issn);

    // 1) uid match, 2) ISSN match, 3) exact-title match — the first
    //    UNCLAIMED local row wins. Two different valid ISSNs identify two
    //    series, so their equal titles must not trigger the last fallback.
    //    If either side lacks a valid ISSN, title matching stays unchanged.
    final byUid = hasUid ? localByUid[uid] : null;
    final byIssn = issn != null ? localByIssn[issn] : null;
    final titleCandidate = localByTitle[inc.title.trim()];
    final titleCandidateIssn = Issn.normalize(titleCandidate?.issn);
    final byTitle =
        issn != null && titleCandidateIssn != null && issn != titleCandidateIssn
        ? null
        : titleCandidate;
    final match = switch ((byUid, byIssn, byTitle)) {
      (final p?, _, _) when !claimedLocalIds.contains(p.id) => (
        p,
        PeriodicalMatchKind.uid,
      ),
      (_, final p?, _) when !claimedLocalIds.contains(p.id) => (
        p,
        PeriodicalMatchKind.issn,
      ),
      (_, _, final p?) when !claimedLocalIds.contains(p.id) => (
        p,
        PeriodicalMatchKind.title,
      ),
      _ => (null, PeriodicalMatchKind.uid),
    };
    final matched = match.$1;
    if (matched != null) {
      claimedLocalIds.add(matched.id);
      // A winner must have a uid for the issues to follow it home. A
      // persisted local row always has one (the repository mints on write);
      // if a hand-built caller ever passes one without, the item pass fails
      // closed instead (orphan → plain book, the importer's W1 rule).
      final winnerUid = matched.periodicalUid?.trim() ?? '';
      if (hasUid && winnerUid.isNotEmpty) winners[uid] = matched;
      if (!matchedLocalSeries.any((p) => p.id == matched.id)) {
        matchedLocalSeries.add(matched);
      }
      if (periodicalMergeEquals(matched, inc)) {
        identical++;
      } else {
        conflicts.add(
          PeriodicalMergeConflict(
            local: matched,
            incoming: inc,
            matchedBy: match.$2,
          ),
        );
      }
      continue;
    }

    // No unclaimed local match. If the uid/ISSN is already held — by a local
    // row an earlier incoming row claimed, or by an earlier incoming row
    // already queued to add — this row can never be inserted (UNIQUE
    // uid/issn). Surface it with the key holder instead (its issues still
    // attach to the holder through [winners]).
    final holder =
        byUid ??
        byIssn ??
        (hasUid ? addedByUid[uid] : null) ??
        (issn != null ? addedByIssn[issn] : null);
    if (holder != null) {
      // The winner must have a uid for the issues to follow. A holder with
      // a blank uid (an added row still awaiting minting) cannot anchor
      // them — the item pass then fails closed (orphan → plain book, the
      // importer's W1 rule) instead of planning a dangling series link.
      final holderUid = holder.periodicalUid?.trim();
      if (hasUid && holderUid != null && holderUid.isNotEmpty) {
        winners[uid] = holder;
      }
      final collidedOnUid =
          byUid != null || (hasUid && addedByUid.containsKey(uid));
      conflicts.add(
        PeriodicalMergeConflict(
          local: holder,
          incoming: inc,
          matchedBy: collidedOnUid
              ? PeriodicalMatchKind.uid
              : PeriodicalMatchKind.issn,
        ),
      );
      continue;
    }

    // Genuinely new to this library → add it (its issues attach to itself).
    toAdd.add(inc);
    if (hasUid) {
      addedByUid[uid] = inc;
      winners[uid] = inc;
    }
    if (issn != null) addedByIssn[issn] = inc;
  }

  return PeriodicalMergePlan(
    toAdd: toAdd,
    conflicts: conflicts,
    identical: identical,
    winners: winners,
    matchedLocalSeries: matchedLocalSeries,
  );
}

/// Field equality for the periodical merge: do the two rows describe the
/// SAME series? The twin of `mergeEquals` for items, with the same three
/// exclusions — the per-device `id` and `addedDate` (local bookkeeping) and
/// `addedBy` (attribution travels) — PLUS `periodicalUid`: an ISSN/title
/// match reconciles two uids by construction, so the uid itself is never a
/// difference worth surfacing. Covers follow the merge cover rule (local
/// file refs are per-device artifacts, M09) and languages compare by the
/// Unicode key (Session 33: `English`/`english` are one language), exactly
/// like the item fields.
bool periodicalMergeEquals(Periodical a, Periodical b) {
  bool coversEqual() {
    if (CoverPaths.isLocal(a.coverUrl) || CoverPaths.isLocal(b.coverUrl)) {
      return true;
    }
    return CoverPaths.remoteUrlOf(a.coverUrl) ==
        CoverPaths.remoteUrlOf(b.coverUrl);
  }

  bool languagesEqual() {
    final ka = a.language == null ? '' : LanguageName.key(a.language!);
    final kb = b.language == null ? '' : LanguageName.key(b.language!);
    return ka == kb;
  }

  return a.title == b.title &&
      a.titleTransliteration == b.titleTransliteration &&
      a.issn == b.issn &&
      a.publisher == b.publisher &&
      languagesEqual() &&
      coversEqual() &&
      a.frequency == b.frequency &&
      a.subscriptionStart == b.subscriptionStart &&
      a.subscriptionEnd == b.subscriptionEnd &&
      a.notes == b.notes &&
      a.location == b.location &&
      a.sourceType == b.sourceType &&
      a.sourceDetail == b.sourceDetail &&
      a.ageGroup == b.ageGroup &&
      a.removed == b.removed &&
      a.removedAt == b.removedAt;
}

/// Re-attaches one incoming item to the winning series of the merge,
/// returning the row the item pass should plan with.
///
/// For an issue whose series the file carries (or the local library already
/// has): the row comes back with the series uid remapped to the winner's
/// and its projected fields (title, publisher, language, year, age group)
/// recomposed from the winner by `IssueProjection` — a file that renamed
/// the series therefore never makes the issue look edited (D.2). Any other
/// row — books, others, and issues whose series is nowhere — is returned
/// unchanged, EXCEPT the last: an issue with no winning series anywhere is
/// a dangling link, which D8/W1 forbid — so it degrades to a plain book
/// keeping every base field, exactly the importer's orphan rule.
CatalogueItem reattachIncomingIssue(
  CatalogueItem item,
  Map<String, Periodical> winners,
  Map<String, Periodical> localSeriesByUid,
) {
  final issue = item.issue;
  if (issue == null) return item;
  final winner =
      winners[issue.periodicalUid.trim()] ??
      localSeriesByUid[issue.periodicalUid.trim()];
  if (winner == null) {
    // No series claims this issue: not in the file's periodicals, not local.
    // The v4 importer already applies this rule at parse time; the planner
    // repeats it so a hand-built payload can never plan a dangling link.
    return CatalogueItem(
      id: item.id,
      itemUid: item.itemUid,
      title: item.title,
      titleTransliteration: item.titleTransliteration,
      author: item.author,
      isbn: item.isbn,
      publisher: item.publisher,
      publishedYear: item.publishedYear,
      genre: item.genre,
      coverUrl: item.coverUrl,
      pageCount: item.pageCount,
      language: item.language,
      notes: item.notes,
      location: item.location,
      sourceType: item.sourceType,
      sourceDetail: item.sourceDetail,
      ageGroup: item.ageGroup,
      addedDate: item.addedDate,
      copyCount: item.copyCount,
      needsMetadata: item.needsMetadata,
      removed: item.removed,
      removedAt: item.removedAt,
      addedBy: item.addedBy,
    );
  }
  final winnerUid = winner.periodicalUid?.trim() ?? '';
  final reanchored = winnerUid.isEmpty || winnerUid == issue.periodicalUid
      ? item
      : item.copyWith(details: issue.copyWith(periodicalUid: winnerUid));
  return IssueProjection.apply(reanchored, winner);
}
