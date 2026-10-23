/// Issue identity keys for dedup/merge (library domain, pure Dart; ADR 0013
/// D6) — the merge planner's twin of `CatalogueSql.issueIdentityKey`.
///
/// Two composers, one rule: the SQL twin backs the UNIQUE partial indexes
/// and the repository's `findIssue` / `findBoundVolume`; THIS one runs in
/// the merge engine, which is pure Dart on a worker isolate (N10-c — no
/// Drift there). They must never disagree: a "same issue" here is a "same
/// issue" in the database. If one changes, change the other in the same
/// commit.
///
/// D6 identity chain for an issue: `itemUid` → the key below → fuzzy title.
/// A DATE-ONLY single issue has no key (like a book without an ISBN): two
/// devices may each catalogue "the October issue" with no number, and a
/// date alone cannot prove them the same physical item — those fall through
/// to the fuzzy pass.
library;

import 'package:pitaka/features/library/domain/value_objects/item_details.dart';

/// The D6 identity key of one issue within its series.
///
/// Why a record (beginner note): the merge engine uses these keys as MAP
/// keys. Records get structural equality for free — two keys with the same
/// fields are the same key — while a hand-written class would need `==` /
/// `hashCode` overrides, which the lints refuse on a class that is not
/// `@immutable` (the domain deliberately keeps plain final classes, N14).
///
/// The fields pack the two D6 shapes:
///  - **numbered issue** (`bound` false): `first` is the volume coalesced
///    to 0 (null and 0 are the same key, matching `COALESCE(volume, 0)` in
///    the SQL twin), `second` is the issue number;
///  - **bound volume** (`bound` true): `first` is the issue date (the
///    first issue in the range), `second` is the bound-until date (the
///    last). A bound volume never has a numbered key — its number, when
///    present, does not identify it (the date range does, D4).
typedef IssueIdentityKey = ({
  bool bound,
  String seriesUid,
  int first,
  int second,
});

/// The D6 identity key of [issue], or null when it has none.
///
/// Mirrors `CatalogueSql.issueIdentityKey` exactly:
///  - a **bound volume** (`boundUntil != null`) keys on both dates; a
///    missing date means no key (a half-known range identifies nothing);
///  - a **single issue** keys on its number (volume coalesced to 0); no
///    number means no key — a date-only issue has no uniqueness guarantee.
IssueIdentityKey? issueIdentityKey(IssueOf issue) {
  if (issue.isBound) {
    final from = issue.issueDate;
    final until = issue.boundUntil;
    if (from == null || until == null) return null;
    return (
      bound: true,
      seriesUid: issue.periodicalUid,
      first: from,
      second: until,
    );
  }
  final number = issue.issueNumber;
  if (number == null) return null;
  return (
    bound: false,
    seriesUid: issue.periodicalUid,
    first: issue.volume ?? 0,
    second: number,
  );
}
