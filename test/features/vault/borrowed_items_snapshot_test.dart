import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/vault/application/build_borrowed_items_snapshot.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';

class _Items implements CatalogueItemRepository {
  _Items(this.rows, {this.failure, this.firstReadGate});
  final Map<int, CatalogueItem> rows;
  final Failure? failure;
  final Completer<void>? firstReadGate;
  final List<int> calls = <int>[];

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    calls.add(id);
    if (calls.length == 1) await firstReadGate?.future;
    final failure = this.failure;
    return failure == null ? right(rows[id]) : left(failure);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Periodicals implements PeriodicalRepository {
  _Periodicals(this.rows, {this.failure});
  final List<Periodical> rows;
  final Failure? failure;
  int calls = 0;

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async {
    calls++;
    final failure = this.failure;
    if (failure != null) return left(failure);
    return right([
      for (final row in rows) PeriodicalSummary(periodical: row, issueCount: 0),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _now = 1000;

Loan _loan({
  required int id,
  int itemId = 1,
  int borrowerId = 1,
  int? due,
  int? returned,
}) => Loan(
  id: id,
  itemId: itemId,
  borrowerId: borrowerId,
  lentDate: 0,
  dueDate: due,
  returnedDate: returned,
);

BuildBorrowedItemsSnapshot _useCase(_Items items, _Periodicals periodicals) =>
    BuildBorrowedItemsSnapshot(items: items, periodicals: periodicals);

void main() {
  test('no active loans performs no catalogue or periodical query', () async {
    final items = _Items(const {});
    final periodicals = _Periodicals(const []);
    final result = await _useCase(items, periodicals)(
      data: VaultData(
        borrowers: const [Borrower(id: 1, name: 'Asha')],
        loans: [_loan(id: 1, returned: 900)],
      ),
      now: _now,
    );

    expect(result.toNullable()!.hasActiveLoans, isFalse);
    expect(items.calls, isEmpty);
    expect(periodicals.calls, 0);
  });

  test(
    'active loans stay separate, deduplicate reads and sort deterministically',
    () async {
      final items = _Items(const {
        1: CatalogueItem(id: 1, title: 'Beta', removed: true),
        2: CatalogueItem(id: 2, title: 'Alpha'),
      });
      final periodicals = _Periodicals(const []);
      final result = await _useCase(items, periodicals)(
        data: VaultData(
          borrowers: const [
            Borrower(id: 1, name: 'Zoe'),
            Borrower(id: 2, name: 'Asha'),
          ],
          loans: [
            _loan(id: 1),
            _loan(id: 2, borrowerId: 2, due: 2000),
            _loan(id: 3, itemId: 2, due: 2000),
            _loan(id: 4, borrowerId: 2, due: 2000),
          ],
        ),
        now: _now,
      );

      final snapshot = result.toNullable()!;
      expect(snapshot.entries.map((entry) => entry.loan.id), [3, 2, 4, 1]);
      expect(snapshot.entries.where((entry) => entry.item.id == 1).length, 3);
      expect(snapshot.entries.first.item.removed, isFalse);
      expect(snapshot.entries.last.item.removed, isTrue);
      expect(items.calls, [1, 2]);
      expect(periodicals.calls, 0);
    },
  );

  test(
    'missing item or borrower references are unresolved, not empty',
    () async {
      final items = _Items(const {1: CatalogueItem(id: 1, title: 'Known')});
      final result = await _useCase(items, _Periodicals(const []))(
        data: VaultData(
          borrowers: const [Borrower(id: 1, name: 'Asha')],
          loans: [_loan(id: 1, itemId: 99), _loan(id: 2, borrowerId: 99)],
        ),
        now: _now,
      );

      final snapshot = result.toNullable()!;
      expect(snapshot.entries, isEmpty);
      expect(snapshot.unresolvedCount, 2);
      expect(snapshot.hasActiveLoans, isTrue);
      expect(items.calls, [99, 1]);
    },
  );

  test(
    'issue covers use series fallback and a missing series means no cover',
    () async {
      final items = _Items(const {
        1: CatalogueItem(
          id: 1,
          title: 'Issue 1',
          details: IssueOf(periodicalUid: 'p1', issueNumber: 1),
        ),
        2: CatalogueItem(
          id: 2,
          title: 'Issue 2',
          details: IssueOf(periodicalUid: 'p2', issueNumber: 2),
        ),
        3: CatalogueItem(
          id: 3,
          title: 'Issue 3',
          coverUrl: 'covers/own.jpg',
          details: IssueOf(periodicalUid: 'p1', issueNumber: 3),
        ),
      });
      final periodicals = _Periodicals(const [
        Periodical(
          id: 1,
          periodicalUid: 'p1',
          title: 'Series',
          coverUrl: 'covers/series.jpg',
        ),
      ]);
      final result = await _useCase(items, periodicals)(
        data: VaultData(
          borrowers: const [Borrower(id: 1, name: 'Asha')],
          loans: [
            _loan(id: 1),
            _loan(id: 2, itemId: 2),
            _loan(id: 3, itemId: 3),
          ],
        ),
        now: _now,
      );

      final entries = result.toNullable()!.entries;
      expect(entries[0].coverUrl, 'covers/series.jpg');
      expect(entries[1].coverUrl, isNull);
      expect(entries[2].coverUrl, 'covers/own.jpg');
      expect(periodicals.calls, 1);
    },
  );

  test('catalogue failure fails the whole snapshot', () async {
    const failure = StorageFailure('private catalogue detail');
    final result =
        await _useCase(
          _Items(const {}, failure: failure),
          _Periodicals(const []),
        )(
          data: VaultData(
            borrowers: const [Borrower(id: 1, name: 'Asha')],
            loans: [_loan(id: 1)],
          ),
          now: _now,
        );
    expect(result.swap().toNullable(), same(failure));
  });

  test('periodical fallback failure fails the whole snapshot', () async {
    const failure = StorageFailure('private periodical detail');
    final result =
        await _useCase(
          _Items(const {
            1: CatalogueItem(
              id: 1,
              title: 'Issue',
              details: IssueOf(periodicalUid: 'p1', issueNumber: 1),
            ),
          }),
          _Periodicals(const [], failure: failure),
        )(
          data: VaultData(
            borrowers: const [Borrower(id: 1, name: 'Asha')],
            loans: [_loan(id: 1)],
          ),
          now: _now,
        );
    expect(result.swap().toNullable(), same(failure));
  });

  test('catalogue reads are sequential per unique id', () async {
    final gate = Completer<void>();
    final items = _Items(const {
      1: CatalogueItem(id: 1, title: 'One'),
      2: CatalogueItem(id: 2, title: 'Two'),
    }, firstReadGate: gate);
    final pending = _useCase(items, _Periodicals(const []))(
      data: VaultData(
        borrowers: const [Borrower(id: 1, name: 'Asha')],
        loans: [_loan(id: 1), _loan(id: 2, itemId: 2)],
      ),
      now: _now,
    );
    await Future<void>.delayed(Duration.zero);
    expect(items.calls, [1]);

    gate.complete();
    await pending;
    expect(items.calls, [1, 2]);
  });
}
