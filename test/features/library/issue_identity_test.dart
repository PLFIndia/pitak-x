import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/merge/issue_identity.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';

/// The D6 key composer (plan S19) — the pure-Dart twin of
/// `CatalogueSql.issueIdentityKey`. The two must never disagree: the SQL side
/// backs the UNIQUE partial indexes, this side runs in the merge engine.
/// The SQL predicates are:
///  - numbered: `periodical_uid = ? AND COALESCE(volume, 0) = ? AND
///    issue_number = ? AND bound_until IS NULL` (issue_number non-null);
///  - bound: `periodical_uid = ? AND issue_date = ? AND bound_until = ?`
///    (both dates non-null).
void main() {
  group('numbered issues', () {
    test('keys on (series, volume coalesced, number)', () {
      const a = IssueOf(periodicalUid: 'p1', volume: 2, issueNumber: 5);
      final key = issueIdentityKey(a)!;
      expect(key.bound, isFalse);
      expect(key.seriesUid, 'p1');
      expect(key.first, 2);
      expect(key.second, 5);
    });

    test('null volume and 0 volume are the same key (COALESCE twin)', () {
      const noVolume = IssueOf(periodicalUid: 'p1', issueNumber: 5);
      const zeroVolume = IssueOf(
        periodicalUid: 'p1',
        volume: 0,
        issueNumber: 5,
      );
      expect(issueIdentityKey(noVolume), issueIdentityKey(zeroVolume));
    });

    test('no number means no key (date-only or date-less)', () {
      const dateOnly = IssueOf(periodicalUid: 'p1', issueDate: 1000);
      const nothing = IssueOf(periodicalUid: 'p1', volume: 3);
      expect(issueIdentityKey(dateOnly), isNull);
      expect(issueIdentityKey(nothing), isNull);
    });
  });

  group('bound volumes', () {
    test('keys on (series, first date, last date)', () {
      const bound = IssueOf(
        periodicalUid: 'p1',
        issueDate: 1000,
        boundUntil: 2000,
      );
      final key = issueIdentityKey(bound)!;
      expect(key.bound, isTrue);
      expect(key.seriesUid, 'p1');
      expect(key.first, 1000);
      expect(key.second, 2000);
    });

    test('a missing date means no key (a half-known range identifies '
        'nothing)', () {
      // IssueOf.validate requires issueDate for a bound volume; the composer
      // still fails closed for a hand-built row.
      const noFrom = IssueOf(periodicalUid: 'p1', boundUntil: 2000);
      expect(issueIdentityKey(noFrom), isNull);
    });

    test('a bound volume never answers the numbered key, even with a '
        'number', () {
      // The SQL twin's numbered index has `WHERE bound_until IS NULL` — a
      // bound volume with a volume/number must not collide with a single
      // issue carrying the same numbers.
      const bound = IssueOf(
        periodicalUid: 'p1',
        volume: 2,
        issueNumber: 5,
        issueDate: 1000,
        boundUntil: 2000,
      );
      const single = IssueOf(periodicalUid: 'p1', volume: 2, issueNumber: 5);
      expect(issueIdentityKey(bound)!.bound, isTrue);
      expect(issueIdentityKey(bound), isNot(issueIdentityKey(single)));
    });
  });

  group('as map keys', () {
    test('structural equality: two composers of the same issue collide in a '
        'map', () {
      final map = <IssueIdentityKey, String>{
        issueIdentityKey(
          const IssueOf(periodicalUid: 'p1', volume: 1, issueNumber: 2),
        )!: 'x',
      };
      final probe = issueIdentityKey(
        const IssueOf(periodicalUid: 'p1', volume: 1, issueNumber: 2),
      );
      expect(map[probe], 'x');
    });

    test('different series never share a key', () {
      final a = issueIdentityKey(
        const IssueOf(periodicalUid: 'p1', issueNumber: 1),
      );
      final b = issueIdentityKey(
        const IssueOf(periodicalUid: 'p2', issueNumber: 1),
      );
      expect(a, isNot(b));
    });
  });
}
