import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/merge/periodical_merge.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// The periodical side of `planMerge` (plan S19): uid → ISSN → exact title,
/// add-only (a matched local row is never overwritten), removal-as-conflict.
void main() {
  Periodical local({
    int id = 1,
    String uid = 'p1',
    String title = 'Chandamama',
    String? issn,
    bool removed = false,
    String? publisher,
  }) => Periodical(
    id: id,
    periodicalUid: uid,
    title: title,
    issn: issn,
    publisher: publisher,
    removed: removed,
    removedAt: removed ? 500 : null,
    addedDate: 1,
  );

  Periodical incoming({
    String? uid = 'p9',
    String title = 'Chandamama',
    String? issn,
    bool removed = false,
    String? publisher,
    PeriodicalFrequency? frequency,
  }) => Periodical(
    periodicalUid: uid,
    title: title,
    issn: issn,
    publisher: publisher,
    frequency: frequency,
    removed: removed,
    removedAt: removed ? 900 : null,
    addedDate: 2,
  );

  group('identity order', () {
    test('uid match wins over a different ISSN and title', () {
      final l = local(issn: '0976-3279');
      final inc = incoming(uid: 'p1', issn: '0027-9358', title: 'Renamed');

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.toAdd, isEmpty);
      expect(plan.conflicts.single.matchedBy, PeriodicalMatchKind.uid);
      expect(plan.conflicts.single.local.id, 1);
    });

    test('ISSN match reconciles the same title under two uids', () {
      final l = local(uid: 'local-uid', issn: '0976-3279');
      final inc = incoming(uid: 'their-uid', issn: '0976-3279');

      final plan = planPeriodicalMerge([l], [inc]);

      // The uid difference is the identity being reconciled, not a field
      // difference — so an ISSN match with equal content is identical.
      expect(plan.conflicts, isEmpty);
      expect(plan.identical, 1);
      expect(plan.toAdd, isEmpty);
      // And the incoming uid's issues re-anchor to the LOCAL series.
      expect(plan.winners['their-uid']?.periodicalUid, 'local-uid');
      expect(plan.matchedLocalSeries.single.id, 1);
    });

    test('a differently-spelled ISSN still matches (defensive normalise) and '
        'the spelling difference is the conflict', () {
      // Real files carry canonical ISSNs (the write gate normalises); a
      // hand-built row must still meet the UNIQUE index's notion of equality.
      final l = local(uid: 'local-uid', issn: '0976-3279');
      final inc = incoming(uid: 'their-uid', issn: '0976 3279');

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.toAdd, isEmpty);
      expect(plan.conflicts.single.matchedBy, PeriodicalMatchKind.issn);
      expect(plan.winners['their-uid']?.periodicalUid, 'local-uid');
    });

    test('exact title is the last resort when neither uid nor ISSN exists', () {
      final l = local(uid: 'local-uid'); // no ISSN
      final inc = incoming(uid: 'their-uid'); // no ISSN, same title

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.identical, 1);
      expect(plan.winners['their-uid']?.id, 1);
    });

    test('same title with different valid ISSNs is a distinct series', () {
      final l = local(uid: 'local-uid', issn: '0976-3279');
      final inc = incoming(uid: 'their-uid', issn: '0027-9358');

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.toAdd.single, same(inc));
      expect(plan.conflicts, isEmpty);
      expect(plan.identical, 0);
      expect(plan.winners['their-uid'], same(inc));
      expect(plan.matchedLocalSeries, isEmpty);
    });

    test('exact title still matches when only one side has an ISSN', () {
      final localMissing = planPeriodicalMerge(
        [local(uid: 'local-uid')],
        [incoming(uid: 'their-uid', issn: '0027-9358')],
      );
      final incomingMissing = planPeriodicalMerge(
        [local(uid: 'local-uid', issn: '0976-3279')],
        [incoming(uid: 'their-uid')],
      );

      for (final plan in [localMissing, incomingMissing]) {
        expect(plan.toAdd, isEmpty);
        expect(plan.conflicts.single.matchedBy, PeriodicalMatchKind.title);
        expect(plan.winners['their-uid']?.periodicalUid, 'local-uid');
      }
    });

    test('a different-cased title is NOT a match (exact means exact)', () {
      final l = local();
      final inc = incoming(title: 'chandamama');

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.toAdd.single.title, 'chandamama');
      expect(plan.identical, 0);
    });
  });

  group('add-only, removal-as-conflict', () {
    test('a field difference on a matched series is a conflict, never an '
        'update', () {
      final l = local(publisher: 'Old Pub');
      final inc = incoming(uid: 'p1', publisher: 'New Pub');

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.toAdd, isEmpty, reason: 'add-only: never overwritten');
      expect(plan.conflicts.single.matchedBy, PeriodicalMatchKind.uid);
      expect(plan.conflicts.single.incoming.publisher, 'New Pub');
      expect(plan.conflicts.single.local.publisher, 'Old Pub');
    });

    test('a removal difference surfaces in BOTH directions', () {
      // Local active, incoming removed:
      final a = planPeriodicalMerge(
        [local()],
        [incoming(uid: 'p1', removed: true)],
      );
      expect(a.conflicts, hasLength(1));
      expect(a.conflicts.single.local.removed, isFalse);
      // Local removed, incoming active (a restore is never applied silently
      // either):
      final b = planPeriodicalMerge(
        [local(removed: true)],
        [incoming(uid: 'p1')],
      );
      expect(b.conflicts, hasLength(1));
      expect(b.conflicts.single.local.removed, isTrue);
    });

    test('a genuinely new series is added and anchors its own issues', () {
      final inc = incoming(title: 'National Geographic');

      final plan = planPeriodicalMerge([local()], [inc]);

      expect(plan.toAdd.single, same(inc));
      expect(plan.winners['p9'], same(inc));
      expect(plan.matchedLocalSeries, isEmpty);
    });

    test('empty inputs are a no-op', () {
      final plan = planPeriodicalMerge(const [], const []);
      expect(plan.isNoOp, isTrue);
      expect(plan.identical, 0);
      expect(plan.winners, isEmpty);
    });
  });

  group('robustness', () {
    test('two incoming series do not fan in onto one local row', () {
      final l = local(issn: '0976-3279');
      final a = incoming(uid: 'u1', issn: '0976-3279');
      final b = incoming(uid: 'u2', issn: '0976-3279', title: 'Other title');

      final plan = planPeriodicalMerge([l], [a, b]);

      // First claims the local row; the second's uid/ISSN are held by the
      // claimed row, so it is a conflict (it can never insert — UNIQUE).
      expect(plan.toAdd, isEmpty);
      expect(plan.identical, 1);
      expect(plan.conflicts.single.incoming.periodicalUid, 'u2');
      expect(plan.conflicts.single.local.id, 1);
      // u2's issues still attach to the winning local series.
      expect(plan.winners['u2']?.periodicalUid, 'p1');
    });

    test('duplicate uid within one file: first added, second conflicted', () {
      final a = incoming(uid: 'dup', title: 'One');
      final b = incoming(uid: 'dup', title: 'Two');

      final plan = planPeriodicalMerge(const [], [a, b]);

      expect(plan.toAdd.single.title, 'One');
      expect(plan.conflicts.single.incoming.title, 'Two');
      expect(plan.conflicts.single.matchedBy, PeriodicalMatchKind.uid);
      // The holder is the earlier INCOMING row (never persisted).
      expect(plan.conflicts.single.local.id, Periodical.emptyId);
      expect(plan.winners['dup']?.title, 'One');
    });

    test('duplicate ISSN under different uids: second re-anchors to the '
        'first', () {
      final a = incoming(uid: 'u1', issn: '0976-3279');
      final b = incoming(uid: 'u2', issn: '0976-3279');

      final plan = planPeriodicalMerge(const [], [a, b]);

      expect(plan.toAdd, hasLength(1));
      expect(plan.conflicts.single.matchedBy, PeriodicalMatchKind.issn);
      expect(plan.winners['u2']?.periodicalUid, 'u1');
    });

    test('same-title rows within one file remain separate adds', () {
      final a = incoming(uid: null);
      final b = incoming(uid: null);

      final plan = planPeriodicalMerge(const [], [a, b]);

      expect(plan.toAdd, [same(a), same(b)]);
      expect(plan.conflicts, isEmpty);
      expect(plan.winners, isEmpty);
    });

    test('a blank uid is ignored by the uid index but still title-matches', () {
      final l = local(uid: 'local-uid');
      final inc = incoming(uid: null); // same title, no uid, no ISSN

      final plan = planPeriodicalMerge([l], [inc]);

      expect(plan.identical, 1);
      expect(plan.conflicts, isEmpty);
      // No uid → no winner entry (nothing can reference it).
      expect(plan.winners, isEmpty);
    });

    test('matchedLocalSeries lists each local winner once', () {
      final l = local(issn: '0976-3279');
      final a = incoming(uid: 'u1', issn: '0976-3279', publisher: 'X');
      final b = incoming(uid: 'u2', issn: '0976-3279', publisher: 'Y');

      final plan = planPeriodicalMerge([l], [a, b]);

      expect(plan.matchedLocalSeries, hasLength(1));
      expect(plan.matchedLocalSeries.single.id, 1);
    });
  });
}
