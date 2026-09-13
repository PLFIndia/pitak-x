import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/background_merge_planner.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// No-ISBN books with unique uids so the plan exercises the fuzzy pass (the
/// expensive part) rather than the O(1) key lookups.
Book _book({required String title, int id = Book.emptyId, String? uid}) =>
    Book(id: id, bookUid: uid, title: title, author: 'A', addedDate: 1);

/// Deterministic 3000 × 3000 fixture (same shape as the N10-b wall-clock
/// test): enough work that a synchronous plan visibly blocks the event loop.
({List<Book> local, List<Book> incoming}) _bigFixture() {
  final rng = Random(7);
  String phrase(int n) =>
      List.generate(n, (_) => 'w${rng.nextInt(400)}x').join(' ');
  return (
    local: [
      for (var i = 0; i < 3000; i++)
        _book(id: i + 1, uid: 'L$i', title: phrase(4)),
    ],
    incoming: [
      for (var i = 0; i < 3000; i++) _book(uid: 'N$i', title: phrase(4)),
    ],
  );
}

void main() {
  group('N10-c — planMergeInBackground', () {
    test('returns exactly the plan planMerge computes', () async {
      final local = [
        _book(id: 1, uid: 'L1', title: 'Alpha Beta Gamma'),
        _book(id: 2, uid: 'L2', title: 'Delta Epsilon'),
        _book(id: 3, uid: 'L3', title: 'Zeta Eta Theta'),
      ];
      final incoming = [
        _book(uid: 'L1', title: 'Alpha Beta Gamma'), // identical (uid match)
        _book(uid: 'L2', title: 'Delta Epsilon CHANGED'), // conflict
        _book(uid: 'N1', title: 'Zeta Eta'), // fuzzy near-miss of L3 (2/3)
        _book(uid: 'N2', title: 'Something Else Entirely'), // plain add
      ];
      final expected = planMerge(local, incoming);
      // Guard the fixture itself: every plan bucket must be non-empty, or the
      // equivalence below would be vacuous for that bucket.
      expect(expected.identical, 1);
      expect(expected.conflicts, hasLength(1));
      expect(expected.possibleDuplicates, hasLength(1));
      expect(expected.toAdd, hasLength(1));

      final actual = await planMergeInBackground(local, incoming);

      expect(actual.identical, expected.identical);
      expect(
        actual.toAdd.map((b) => b.bookUid),
        expected.toAdd.map((b) => b.bookUid),
      );
      expect(
        actual.conflicts.map((c) => (c.local.id, c.incoming.bookUid)),
        expected.conflicts.map((c) => (c.local.id, c.incoming.bookUid)),
      );
      expect(
        actual.possibleDuplicates.map(
          (d) => (d.local.id, d.incoming.bookUid, d.similarity, d.reason),
        ),
        expected.possibleDuplicates.map(
          (d) => (d.local.id, d.incoming.bookUid, d.similarity, d.reason),
        ),
      );
      // Entities survive the isolate hop with their fields intact.
      expect(actual.toAdd.single.title, 'Something Else Entirely');
      expect(actual.toAdd.single.author, 'A');
    });

    test('a timer fires while a large plan is still running', () async {
      // Same proof shape as N10-a: a 1 ms Timer on this isolate can only run
      // mid-plan if the plan does not block this isolate. A synchronous
      // planMerge holds the event loop until it returns.
      final fx = _bigFixture();
      final fired = Completer<int>();
      final sw = Stopwatch()..start();
      Timer(const Duration(milliseconds: 1), () {
        fired.complete(sw.elapsedMilliseconds);
      });
      final work = planMergeInBackground(fx.local, fx.incoming);
      final firedAt = await fired.future;
      final plan = await work;
      final total = sw.elapsedMilliseconds;
      expect(plan.toAdd.length + plan.possibleDuplicates.length, 3000);
      expect(
        firedAt,
        lessThan(total ~/ 2),
        reason:
            'the timer must fire while the plan is still running '
            '(fired at $firedAt ms, plan took $total ms)',
      );
    });

    test('empty inputs produce an empty plan without error', () async {
      final plan = await planMergeInBackground(const [], const []);
      expect(plan.isNoOp, isTrue);
      expect(plan.identical, 0);
    });
  });
}
