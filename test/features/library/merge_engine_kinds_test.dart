import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// `planMerge` with item kinds and periodicals (plan S19; ADR 0013 D6):
/// the issue identity chain, the kind-mismatch conflict rule, the per-kind
/// fuzzy pools, and the series re-anchoring / re-projection the item pass
/// sees. The periodical-only rules have their own file
/// (`periodical_merge_test.dart`); these tests pin the COMPOSITION.
void main() {
  const series = Periodical(
    id: 1,
    periodicalUid: 'per-1',
    title: 'Chandamama',
    issn: '0976-3279',
    publisher: 'Times Press',
    language: 'hi',
    addedDate: 1,
  );

  CatalogueItem issue({
    int id = 0,
    String? uid,
    String seriesUid = 'per-1',
    int? volume,
    int? number,
    int? date,
    int? until,
    String? label,
    String title = '',
    int copyCount = 1,
  }) => CatalogueItem(
    id: id,
    itemUid: uid,
    title: title,
    addedDate: 1,
    copyCount: copyCount,
    details: IssueOf(
      periodicalUid: seriesUid,
      volume: volume,
      issueNumber: number,
      issueDate: date,
      boundUntil: until,
      label: label,
    ),
  );

  group('D6 — issue identity chain', () {
    test('a numbered issue matches by (series, volume, number) when uids '
        'differ', () {
      // Two devices catalogued the same issue independently: different
      // itemUids, same series + number.
      final localIssue = issue(id: 5, uid: 'mine', volume: 2, number: 3);
      final inc = issue(uid: 'theirs', volume: 2, number: 3);

      final plan = planMerge(
        [localIssue],
        [inc],
        localPeriodicals: const [series],
        incomingPeriodicals: const [series],
      );

      expect(plan.identical, 1);
      expect(plan.toAdd, isEmpty);
      expect(plan.conflicts, isEmpty);
    });

    test('volume null and volume 0 are the same key (COALESCE parity)', () {
      // A stored row never has volume 0 (validation requires ≥ 1), so the
      // coalesce only matters at the index/identity level — that parity is
      // pinned in issue_identity_test. Here: two null-volume issues match.
      final localIssue = issue(id: 5, uid: 'mine', number: 3);
      final inc = issue(uid: 'theirs', number: 3);

      final plan = planMerge(
        [localIssue],
        [inc],
        localPeriodicals: const [series],
        incomingPeriodicals: const [series],
      );

      expect(plan.identical, 1);
    });

    test('a bound volume matches by its date range; a stray number is a '
        'field difference, not identity', () {
      final localBound = issue(id: 5, uid: 'mine', date: 1000, until: 2000);
      // Same range, and the incoming one even carries a number — the bound
      // key is the dates (D4), so the rows MATCH; the number one device
      // recorded and the other did not is an ordinary field conflict.
      final inc = issue(uid: 'theirs', number: 7, date: 1000, until: 2000);

      final plan = planMerge(
        [localBound],
        [inc],
        localPeriodicals: const [series],
        incomingPeriodicals: const [series],
      );

      expect(plan.toAdd, isEmpty);
      final conflict = plan.conflicts.single;
      expect(conflict.matchedBy, MatchKind.issueIdentity);
      expect(
        mergeDifferences(conflict.local, conflict.incoming).map((d) => d.field),
        [MergeField.issue],
      );
    });

    test('same number in DIFFERENT series never matches', () {
      const otherSeries = Periodical(
        id: 2,
        periodicalUid: 'per-2',
        title: 'National Geographic',
        addedDate: 1,
      );
      final localIssue = issue(id: 5, uid: 'mine', number: 3);
      final inc = issue(uid: 'theirs', seriesUid: 'per-2', number: 3);

      final plan = planMerge(
        [localIssue],
        [inc],
        localPeriodicals: const [series, otherSeries],
        incomingPeriodicals: const [otherSeries],
      );

      expect(plan.identical, 0);
      expect(plan.toAdd.single.itemUid, 'theirs');
    });

    test('a key match with differing own-fields is a conflict, matched by '
        'issueIdentity', () {
      final localIssue = issue(id: 5, uid: 'mine', number: 3);
      final inc = issue(uid: 'theirs', number: 3, label: 'Dasara special');

      final plan = planMerge(
        [localIssue],
        [inc],
        localPeriodicals: const [series],
        incomingPeriodicals: const [series],
      );

      final conflict = plan.conflicts.single;
      expect(conflict.matchedBy, MatchKind.issueIdentity);
      final diffs = mergeDifferences(conflict.local, conflict.incoming);
      expect(diffs.map((d) => d.field), [MergeField.issue]);
      expect(diffs.single.incoming, contains('Dasara special'));
    });

    test('a date-only issue has no key: same date fuzzes into a possible '
        'duplicate, a different date is added', () {
      final localA = issue(
        id: 1,
        uid: 'mine-a',
        date: 1768478400000, // Jan 2026
      );
      final localB = issue(
        id: 2,
        uid: 'mine-b',
        date: 1771171200000, // Feb 2026
      );
      final sameAsA = issue(uid: 'theirs-a', date: 1768478400000);
      final novel = issue(uid: 'theirs-b', date: 1780000000000); // May 2026

      final plan = planMerge(
        [localA, localB],
        [sameAsA, novel],
        localPeriodicals: const [series],
        incomingPeriodicals: const [series],
      );

      // The date-only issues compose the same title only when the date is
      // the same — so 'theirs-a' is surfaced against localA (identical
      // tokens → 1.0) while the genuinely different month is added.
      expect(plan.possibleDuplicates.single.incoming.itemUid, 'theirs-a');
      expect(plan.possibleDuplicates.single.local.id, 1);
      expect(plan.toAdd.single.itemUid, 'theirs-b');
    });

    test('an in-file issue-key collision is surfaced, never added twice', () {
      // Two rows of the same file with the same (series, number): the second
      // can never insert (UNIQUE index) — same rule as the ISBN twin.
      final a = issue(uid: 'u1', number: 3);
      final b = issue(uid: 'u2', number: 3);

      final plan = planMerge(
        const [],
        [a, b],
        incomingPeriodicals: const [series],
      );

      expect(plan.toAdd.single.itemUid, 'u1');
      final dup = plan.possibleDuplicates.single;
      expect(dup.reason, DuplicateReason.identityKey);
      expect(dup.incoming.itemUid, 'u2');
    });
  });

  group('D6/D8 — kind mismatch on a uid match', () {
    test('same uid, book vs issue → conflict, never an update', () {
      // The title matches the incoming issue's projected title, so the KIND
      // row is the only difference the diff card lists.
      const localBook = CatalogueItem(
        id: 7,
        itemUid: 'u1',
        title: 'Chandamama — No 3',
        addedDate: 1,
      );
      final inc = issue(uid: 'u1', number: 3);

      final plan = planMerge(
        [localBook],
        [inc],
        incomingPeriodicals: const [series],
      );

      expect(plan.toAdd, isEmpty);
      final conflict = plan.conflicts.single;
      expect(conflict.matchedBy, MatchKind.uid);
      // The diff card leads with the KIND row (the projected publisher /
      // language the issue carries and the book lacks follow it).
      final diffs = mergeDifferences(conflict.local, conflict.incoming);
      expect(diffs.first.field, MergeField.kind);
      expect(diffs.first.local, 'Book');
      expect(diffs.first.incoming, 'Magazine issue');
    });

    test('same uid, same kind, equal content is still identical', () {
      final localIssue = issue(id: 7, uid: 'u1', number: 3);
      final inc = issue(uid: 'u1', number: 3);

      final plan = planMerge(
        [localIssue],
        [inc],
        localPeriodicals: const [series],
        incomingPeriodicals: const [series],
      );

      expect(plan.isNoOp, isTrue);
      expect(plan.identical, 1);
    });
  });

  group('per-kind fuzzy pools', () {
    test('a no-ISBN book never fuzzy-matches a local issue or other', () {
      // The local issue's projected title shares every token with the
      // incoming book — before S19 this surfaced a phantom duplicate.
      final localIssue = issue(id: 1, uid: 'i1', number: 3);
      const localOther = CatalogueItem(
        id: 2,
        itemUid: 'o1',
        title: 'Kabir Ke Dohe',
        addedDate: 1,
        details: OtherItemOf(),
      );
      const inc = CatalogueItem(
        itemUid: 'new',
        title: 'Kabir Ke Dohe',
        addedDate: 2,
      );

      final plan = planMerge(
        [localIssue, localOther],
        [inc],
        localPeriodicals: const [series],
      );

      expect(plan.possibleDuplicates, isEmpty);
      expect(plan.toAdd.single.itemUid, 'new');
    });

    test('an incoming other fuzzy-matches only local others', () {
      const localBook = CatalogueItem(
        id: 1,
        itemUid: 'b1',
        title: 'Kabir Ke Dohe',
        addedDate: 1,
      );
      const localOther = CatalogueItem(
        id: 2,
        itemUid: 'o1',
        title: 'Kabir Ke Dohe',
        addedDate: 1,
        details: OtherItemOf(),
      );
      const inc = CatalogueItem(
        itemUid: 'new',
        title: 'Kabir ke Dohe',
        addedDate: 2,
        details: OtherItemOf(),
      );

      final plan = planMerge([localBook, localOther], [inc]);

      final dup = plan.possibleDuplicates.single;
      expect(dup.local.id, 2, reason: 'the other, not the book');
    });
  });

  group('series re-anchoring (risk D.2)', () {
    test('an ISSN-matched series (different uid) re-anchors its incoming '
        'issues to the local uid', () {
      const localSeries = Periodical(
        id: 1,
        periodicalUid: 'local-uid',
        title: 'Chandamama',
        issn: '0976-3279',
        addedDate: 1,
      );
      const theirSeries = Periodical(
        periodicalUid: 'their-uid',
        title: 'Chandamama',
        issn: '0976-3279',
        addedDate: 2,
      );
      final localIssue = issue(
        id: 5,
        uid: 'mine',
        seriesUid: 'local-uid',
        number: 3,
      );
      final inc = issue(uid: 'theirs', seriesUid: 'their-uid', number: 3);

      final plan = planMerge(
        [localIssue],
        [inc],
        localPeriodicals: const [localSeries],
        incomingPeriodicals: const [theirSeries],
      );

      // The remap made the D6 key match possible at all.
      expect(plan.identical, 1);
      expect(plan.toAdd, isEmpty);
    });

    test('different ISSNs keep same-title series and issues out of review', () {
      const theirSeries = Periodical(
        periodicalUid: 'their-uid',
        title: 'Chandamama',
        issn: '0027-9358',
        addedDate: 2,
      );
      final localIssue = issue(id: 5, uid: 'mine', number: 3);
      final incomingIssue = issue(
        uid: 'theirs',
        seriesUid: 'their-uid',
        number: 3,
      );

      final plan = planMerge(
        [localIssue],
        [incomingIssue],
        localPeriodicals: const [series],
        incomingPeriodicals: const [theirSeries],
      );

      expect(plan.periodicalsToAdd.single, same(theirSeries));
      expect(plan.periodicalConflicts, isEmpty);
      expect(plan.matchedLocalSeries, isEmpty);
      expect(plan.toAdd.single.itemUid, 'theirs');
      expect(plan.toAdd.single.issue?.periodicalUid, 'their-uid');
      expect(plan.conflicts, isEmpty);
      expect(plan.possibleDuplicates, isEmpty);
      expect(plan.hasReviewItems, isFalse);
    });

    test('a renamed series does not storm per-issue title conflicts', () {
      // This device renamed the series (issues re-projected to the NEW name
      // at edit time); the other device still exports the OLD name and its
      // old-named issues. The merge keeps the local series (add-only) and
      // must surface ONE series conflict and ZERO issue conflicts.
      const renamed = Periodical(
        id: 1,
        periodicalUid: 'per-1',
        title: 'Chandamama New',
        issn: '0976-3279',
        addedDate: 1,
      );
      const old = Periodical(
        periodicalUid: 'per-1',
        title: 'Chandamama',
        issn: '0976-3279',
        addedDate: 1,
      );
      // The local store is mid-import-stale: the rows carry the OLD title.
      final staleLocal = issue(
        id: 5,
        uid: 'i1',
        number: 3,
        title: 'Chandamama — No 3',
      );
      final incomingIssue = issue(
        uid: 'i1',
        number: 3,
        title: 'Chandamama — No 3',
      );

      final plan = planMerge(
        [staleLocal],
        [incomingIssue],
        localPeriodicals: const [renamed],
        incomingPeriodicals: const [old],
      );

      expect(plan.periodicalConflicts, hasLength(1));
      expect(plan.conflicts, isEmpty, reason: 'no issue storm');
      expect(plan.identical, 1);
      expect(plan.matchedLocalSeries.single.title, 'Chandamama New');
    });

    test('an incoming issue whose series is NOWHERE degrades to a plain '
        'book', () {
      // The v4 importer applies this orphan rule at parse time; the planner
      // repeats it so a hand-built payload never plans a dangling link.
      final orphan = issue(uid: 'orphan', seriesUid: 'ghost', number: 1);

      final plan = planMerge(const [], [orphan]);

      final added = plan.toAdd.single;
      expect(added.details, isNull);
      expect(added.kind.name, 'book');
      expect(added.itemUid, 'orphan');
    });

    test('periodical buckets participate in isNoOp', () {
      const newSeries = Periodical(
        periodicalUid: 'per-new',
        title: 'National Geographic',
        addedDate: 2,
      );
      final plan = planMerge(
        const [],
        const [],
        incomingPeriodicals: const [newSeries],
      );
      expect(plan.isNoOp, isFalse);
      expect(plan.periodicalsToAdd.single.title, 'National Geographic');

      expect(
        planMerge(
          const [],
          const [],
          localPeriodicals: const [series],
          incomingPeriodicals: const [series],
        ).isNoOp,
        isTrue,
      );
    });
  });
}
