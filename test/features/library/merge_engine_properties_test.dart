import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

import '../../support/fuzz.dart';

/// Property tests for `planMerge` (architecture.md B3). The merge engine
/// decides what a restore/import writes — a partition bug here is a
/// data-loss bug, so the invariants are tested on [Fuzz.cases] seeded random
/// libraries (one generator per case, so a printed seed replays one case),
/// not a couple of hand-written cases.
void main() {
  const cases = Fuzz.cases;

  /// A random book. ISBNs/uids are drawn from a SMALL pool so collisions
  /// (the interesting cases) actually happen.
  Book randomBook(Fuzz fuzz, {required int id}) {
    final hasIsbn = fuzz.nextInt(2) == 0;
    return Book(
      id: id,
      title: 'Title ${fuzz.nextInt(20)}',
      author: 'Author ${fuzz.nextInt(10)}',
      bookUid: fuzz.nextInt(3) == 0 ? 'uid-${fuzz.nextInt(8)}' : null,
      isbn: hasIsbn ? 'isbn-${fuzz.nextInt(8)}' : null,
      publisher: fuzz.nextInt(2) == 0 ? 'Pub ${fuzz.nextInt(4)}' : null,
      pageCount: fuzz.nextInt(3) == 0 ? 100 + fuzz.nextInt(400) : null,
      language: fuzz.nextInt(2) == 0 ? 'en' : null,
      addedDate: fuzz.nextInt(1000000),
      copyCount: 1 + fuzz.nextInt(3),
      removed: fuzz.nextInt(10) == 0,
    );
  }

  /// Every incoming book must land in EXACTLY ONE bucket of the plan.
  /// Identifies each bucket's membership by identity of the incoming Book
  /// objects (planMerge never copies books into the plan — the same
  /// instances appear in toAdd/conflicts/possibleDuplicates).
  void expectPartition(MergePlan plan, List<Book> incoming) {
    final bucketed = <Book>[
      ...plan.toAdd,
      ...plan.conflicts.map((c) => c.incoming),
      ...plan.possibleDuplicates.map((d) => d.incoming),
    ];
    // `identical` is a COUNT, not a list (the engine discards no-op rows),
    // so the partition identity is checked by cardinality + membership:
    // every bucketed row is a distinct incoming instance, and
    // |bucketed| + identical == |incoming|.
    expect(
      bucketed.toSet().length,
      bucketed.length,
      reason: 'an incoming book appears in two buckets',
    );
    expect(
      bucketed.length + plan.identical,
      incoming.length,
      reason:
          'partition is incomplete: buckets+identical '
          'must equal |incoming|',
    );
    for (final book in bucketed) {
      expect(
        incoming.contains(book),
        isTrue,
        reason: 'a planned book is not one of the incoming rows',
      );
    }
  }

  test('partition is complete and disjoint on random inputs', () {
    for (var i = 0; i < cases; i++) {
      final fuzz = Fuzz.forCase(i);
      final local = [
        for (var j = 0; j < fuzz.nextInt(12); j++) randomBook(fuzz, id: j + 1),
      ];
      final incoming = [
        for (var j = 0; j < fuzz.nextInt(12); j++) randomBook(fuzz, id: 0),
      ];
      final plan = planMerge(local, incoming);
      try {
        expectPartition(plan, incoming);
      } catch (e) {
        fail('partition violated on case $i (seed ${fuzz.seed}): $e');
      }
    }
  });

  test('planMerge(existing, []) is empty', () {
    for (var i = 0; i < cases; i++) {
      final fuzz = Fuzz.forCase(i);
      final local = [
        for (var j = 0; j < fuzz.nextInt(12); j++) randomBook(fuzz, id: j + 1),
      ];
      final plan = planMerge(local, const []);
      expect(
        plan.isNoOp && plan.identical == 0,
        isTrue,
        reason:
            'empty incoming on case $i (seed ${fuzz.seed}) '
            'produced $plan',
      );
    }
  });

  test(
    'the plan is identical under any shuffle when incoming keys are unique',
    () {
      // Design note (library_merge_engine.dart, "identity keys already spoken
      // for"): when two rows of the SAME file share a uid/ISBN, the first one
      // wins `toAdd` and the rest are surfaced — an intentional
      // order-dependent choice (some row must win, and file order is the only
      // honest tie-break). The shuffle-invariance property is therefore
      // asserted where it is meaningful: distinct identity keys, so no
      // tie-break ever fires.
      for (var i = 0; i < cases; i++) {
        final fuzz = Fuzz.forCase(i);
        final local = [
          for (var j = 0; j < fuzz.nextInt(10); j++)
            randomBook(fuzz, id: j + 1),
        ];
        // Distinct keys per row: unique isbn/uid drawn from the case index.
        final incoming = [
          for (var j = 0; j < fuzz.nextInt(10); j++)
            Book(
              title: 'Title ${fuzz.nextInt(20)}',
              author: 'Author ${fuzz.nextInt(10)}',
              bookUid: 'case-$i-uid-$j',
              isbn: 'case-$i-isbn-$j',
              addedDate: fuzz.nextInt(1000000),
            ),
        ];
        final shuffled = List<Book>.of(incoming)..shuffle(fuzzRandom(fuzz));

        final a = planMerge(local, incoming);
        final b = planMerge(local, shuffled);

        String signature(MergePlan p) {
          String sig(Book book) =>
              '${book.title}|${book.author}|${book.isbn}|${book.bookUid}';
          final toAdd = p.toAdd.map(sig).toList()..sort();
          final conflicts =
              p.conflicts
                  .map((c) => '${sig(c.local)}<>${sig(c.incoming)}')
                  .toList()
                ..sort();
          final dupes =
              p.possibleDuplicates
                  .map((d) => '${sig(d.local)}~${sig(d.incoming)}')
                  .toList()
                ..sort();
          return 'add:$toAdd;conf:$conflicts;dup:$dupes;ident:${p.identical}';
        }

        expect(
          signature(a),
          signature(b),
          reason: 'shuffle changed the plan on case $i (seed ${fuzz.seed})',
        );
      }
    },
  );

  test(
    'in-file identity collisions are flagged, never silently added twice',
    () {
      // Companion property for the order-dependent case above: every row past
      // the first that reuses a key must land in possibleDuplicates (UNIQUE
      // index protection), regardless of order.
      for (var i = 0; i < cases; i++) {
        final fuzz = Fuzz.forCase(i);
        final incoming = [
          for (var j = 0; j < 2 + fuzz.nextInt(4); j++)
            Book(title: 'Shared $j', isbn: 'same-isbn-$i', addedDate: j),
        ];
        final plan = planMerge(const [], incoming);
        expect(
          plan.toAdd.length,
          1,
          reason: 'case $i: exactly one row may win the shared key',
        );
        expect(
          plan.possibleDuplicates.length,
          incoming.length - 1,
          reason: 'case $i: the rest must be flagged for review',
        );
        expectPartition(plan, incoming);
      }
    },
  );
}

/// planMerge is order-sensitive only in WHICH duplicate row wins; the bucket
/// CONTENTS must be stable. A Random view over the same sequence keeps the
/// shuffle reproducible per case.
Random fuzzRandom(Fuzz fuzz) => _FuzzRandom(fuzz);

final class _FuzzRandom implements Random {
  _FuzzRandom(this._fuzz);
  final Fuzz _fuzz;
  @override
  int nextInt(int max) => _fuzz.nextInt(max);
  @override
  double nextDouble() => _fuzz.nextInt(1 << 32) / (1 << 32);
  @override
  bool nextBool() => _fuzz.nextInt(2) == 0;
}
