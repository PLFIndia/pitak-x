/// In-memory fakes shared by the periodical / issue use-case tests (plan
/// S12). Each fake records the calls it receives and can be told to fail a
/// given method, so every success and failure path of a use case can be
/// driven without a database. The fakes honour the repository CONTRACTS the
/// use cases rely on (uid minted on insert, stored uid kept on update, a
/// `Left` inside `runInTransaction` rolls the fake's rows back) — the
/// contracts themselves are proven against Drift in the repository tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Unwraps a `Right` or fails the test naming the failure.
T ok<T>(Either<Failure, T> e) =>
    e.getOrElse((f) => fail('unexpected failure: $f'));

/// Unwraps a `Left` or fails the test.
Failure failureOf<T>(Either<Failure, T> e) =>
    e.getLeft().toNullable() ?? fail('expected a failure, got $e');

/// Periodicals store: rows by id, plus the issues of each series (by uid)
/// that the series-side reads answer from.
class FakePeriodicals implements PeriodicalRepository {
  /// Stored periodicals by id.
  final Map<int, Periodical> rows = {};

  /// Issues per series uid, as `issuesOf` / `countIssues` / `findIssue` /
  /// `findBoundVolume` see them.
  final Map<String, List<CatalogueItem>> issues = {};

  /// Method names in call order.
  final List<String> calls = [];

  /// Set one of these to make that method answer `Left(failure)`.
  Failure? getByIdFailure;
  Failure? findByUidFailure;
  Failure? findByIssnFailure;
  Failure? insertFailure;
  Failure? updateFailure;
  Failure? deleteFailure;
  Failure? countIssuesFailure;
  Failure? issuesOfFailure;
  Failure? findIssueFailure;
  Failure? findBoundVolumeFailure;

  int _nextId = 1;

  /// Stores [periodical] directly (no validation) and returns it with an
  /// id and a uid, like a row already in the database.
  Periodical seed(Periodical periodical) {
    final id = _nextId++;
    final uid = periodical.periodicalUid ?? 'uid-$id';
    final stored = periodical.copyWith(id: id, periodicalUid: uid);
    rows[id] = stored;
    return stored;
  }

  @override
  Future<Either<Failure, Periodical?>> getById(int id) async {
    calls.add('getById');
    if (getByIdFailure != null) return left(getByIdFailure!);
    return right(rows[id]);
  }

  @override
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid) async {
    calls.add('findByUid');
    if (findByUidFailure != null) return left(findByUidFailure!);
    return right(
      rows.values.where((p) => p.periodicalUid == periodicalUid).firstOrNull,
    );
  }

  @override
  Future<Either<Failure, Periodical?>> findByIssn(String issn) async {
    calls.add('findByIssn:$issn');
    if (findByIssnFailure != null) return left(findByIssnFailure!);
    return right(rows.values.where((p) => p.issn == issn).firstOrNull);
  }

  @override
  Future<Either<Failure, Periodical>> insert(Periodical periodical) async {
    calls.add('insert');
    if (insertFailure != null) return left(insertFailure!);
    return right(seed(periodical));
  }

  @override
  Future<Either<Failure, Periodical>> update(Periodical periodical) async {
    calls.add('update');
    if (updateFailure != null) return left(updateFailure!);
    final existing = rows[periodical.id];
    if (periodical.id == Periodical.emptyId || existing == null) {
      return left(const NotFoundFailure());
    }
    // Contract: the stored uid always wins.
    final stored = periodical.copyWith(periodicalUid: existing.periodicalUid);
    rows[periodical.id] = stored;
    return right(stored);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    calls.add('delete');
    if (deleteFailure != null) return left(deleteFailure!);
    rows.remove(id);
    return right(unit);
  }

  @override
  Future<Either<Failure, int>> countIssues(String periodicalUid) async {
    calls.add('countIssues');
    if (countIssuesFailure != null) return left(countIssuesFailure!);
    return right(issues[periodicalUid]?.length ?? 0);
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> issuesOf(
    String periodicalUid,
  ) async {
    calls.add('issuesOf');
    if (issuesOfFailure != null) return left(issuesOfFailure!);
    return right(List.of(issues[periodicalUid] ?? const []));
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findIssue({
    required String periodicalUid,
    required int? volume,
    required int issueNumber,
  }) async {
    calls.add('findIssue');
    if (findIssueFailure != null) return left(findIssueFailure!);
    return right(
      (issues[periodicalUid] ?? const []).where((row) {
        final issue = row.issue!;
        return !issue.isBound &&
            (issue.volume ?? 0) == (volume ?? 0) &&
            issue.issueNumber == issueNumber;
      }).firstOrNull,
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findBoundVolume({
    required String periodicalUid,
    required int issueDate,
    required int boundUntil,
  }) async {
    calls.add('findBoundVolume');
    if (findBoundVolumeFailure != null) return left(findBoundVolumeFailure!);
    return right(
      (issues[periodicalUid] ?? const []).where((row) {
        final issue = row.issue!;
        return issue.isBound &&
            issue.issueDate == issueDate &&
            issue.boundUntil == boundUntil;
      }).firstOrNull,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

/// Catalogue item store: rows by id, with a transaction that rolls the rows
/// back when the callback answers `Left` (the real repository's contract).
class FakeItems implements CatalogueItemRepository {
  /// Stored items by id.
  final Map<int, CatalogueItem> rows = {};

  /// Every row handed to `insert`, in order.
  final List<CatalogueItem> inserted = [];

  /// Every row handed to `update`, in order (including a refused one).
  final List<CatalogueItem> updated = [];

  /// Method names in call order; `update` entries carry whether the call
  /// ran inside `runInTransaction`.
  final List<String> calls = [];

  /// Set to make that method answer `Left(failure)`.
  Failure? getByIdFailure;
  Failure? insertFailure;

  /// When set, the Nth `update` call (1-based) answers [updateFailure] —
  /// the "mid-way failure" of a multi-row write.
  int? failUpdateAt;

  /// The failure [failUpdateAt] answers with.
  Failure updateFailure = const StorageFailure('synthetic update failure');

  /// How many times `runInTransaction` was entered.
  int transactions = 0;

  /// True after a transaction callback answered `Left` (rows restored).
  bool rolledBack = false;

  bool _inTransaction = false;
  int _updateCalls = 0;
  int _nextId = 1;

  /// Stores [item] directly and returns it with an id and a uid.
  CatalogueItem seed(CatalogueItem item) {
    final id = _nextId++;
    final stored = item.copyWith(id: id, itemUid: item.itemUid ?? 'item-$id');
    rows[id] = stored;
    return stored;
  }

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    calls.add('getById');
    if (getByIdFailure != null) return left(getByIdFailure!);
    return right(rows[id]);
  }

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    calls.add('insert');
    inserted.add(book);
    if (insertFailure != null) return left(insertFailure!);
    return right(seed(book));
  }

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    calls.add(_inTransaction ? 'update(in transaction)' : 'update');
    updated.add(book);
    _updateCalls++;
    if (failUpdateAt == _updateCalls) return left(updateFailure);
    final existing = rows[book.id];
    if (book.id == CatalogueItem.emptyId || existing == null) {
      return left(const NotFoundFailure());
    }
    final stored = book.copyWith(itemUid: existing.itemUid);
    rows[book.id] = stored;
    return right(stored);
  }

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    transactions++;
    _inTransaction = true;
    // Snapshot + restore stands in for Drift's rollback, so a test can see
    // that a `Left` returned INSIDE the callback undoes the earlier writes.
    final snapshot = Map.of(rows);
    try {
      final result = await action();
      if (result.isLeft()) {
        rows
          ..clear()
          ..addAll(snapshot);
        rolledBack = true;
      }
      return result;
    } finally {
      _inTransaction = false;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}
