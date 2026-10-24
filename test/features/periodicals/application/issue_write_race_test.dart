import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/add_issue_use_case.dart';
import 'package:pitaka/features/periodicals/application/delete_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/application/update_issue_use_case.dart';
import 'package:pitaka/features/periodicals/application/update_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';
import 'package:pitaka/features/periodicals/infrastructure/drift_periodical_repository.dart';

import '../../../support/async_value_gate.dart';

/// Issue-side series reads: record transaction depth and park AFTER the real
/// lookup has captured its row.
class _IssuePeriodicals extends DriftPeriodicalRepository {
  _IssuePeriodicals(super.db, this._depth);

  final int Function() _depth;
  final List<int> seriesLookupDepths = [];
  final List<int> identityLookupDepths = [];

  AsyncValueGate<void>? afterSeriesLookup;

  @override
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid) async {
    seriesLookupDepths.add(_depth());
    final result = await super.findByUid(periodicalUid);
    final gate = afterSeriesLookup;
    if (gate != null) {
      afterSeriesLookup = null;
      await gate.wait();
    }
    return result;
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findIssue({
    required String periodicalUid,
    required int? volume,
    required int issueNumber,
  }) {
    identityLookupDepths.add(_depth());
    return super.findIssue(
      periodicalUid: periodicalUid,
      volume: volume,
      issueNumber: issueNumber,
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findBoundVolume({
    required String periodicalUid,
    required int issueDate,
    required int boundUntil,
  }) {
    identityLookupDepths.add(_depth());
    return super.findBoundVolume(
      periodicalUid: periodicalUid,
      issueDate: issueDate,
      boundUntil: boundUntil,
    );
  }
}

/// Issue-side item calls: record every required stage and gate the REAL write.
class _IssueItems extends DriftCatalogueItemRepository {
  _IssueItems(super.db);

  int depth = 0;
  int transactionCalls = 0;
  final List<int> getByIdDepths = [];
  final List<int> insertDepths = [];
  final List<int> updateDepths = [];

  AsyncValueGate<void>? beforeInsert;
  AsyncValueGate<void>? beforeUpdate;

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    transactionCalls++;
    depth++;
    try {
      return await super.runInTransaction(action);
    } finally {
      depth--;
    }
  }

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) {
    getByIdDepths.add(depth);
    return super.getById(id);
  }

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    insertDepths.add(depth);
    final gate = beforeInsert;
    if (gate != null) {
      beforeInsert = null;
      await gate.wait();
    }
    return super.insert(book);
  }

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    updateDepths.add(depth);
    final gate = beforeUpdate;
    if (gate != null) {
      beforeUpdate = null;
      await gate.wait();
    }
    return super.update(book);
  }
}

/// Rename-side items: park before UpdatePeriodicalUseCase opens its
/// transaction.
class _CompetitorItems extends DriftCatalogueItemRepository {
  _CompetitorItems(super.db);

  AsyncValueGate<void>? beforeTransaction;

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    final gate = beforeTransaction;
    if (gate != null) {
      beforeTransaction = null;
      await gate.wait();
    }
    return super.runInTransaction(action);
  }
}

/// Delete-side series: park after the use case's count-zero precheck but before
/// the repository's authoritative count-and-delete transaction.
class _CompetitorPeriodicals extends DriftPeriodicalRepository {
  _CompetitorPeriodicals(super.db);

  AsyncValueGate<void>? beforeDelete;
  int deleteCalls = 0;

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    deleteCalls++;
    final gate = beforeDelete;
    if (gate != null) {
      beforeDelete = null;
      await gate.wait();
    }
    return super.delete(id);
  }
}

enum _IssueWrite { insert, update }

/// S3/M1: exact interleavings against one REAL Drift database. Every facade
/// shares that database, but issue and competitor operations have distinct
/// repositories so their gates and transaction counters cannot contaminate
/// each other.
void main() {
  final october2026 = DateTime.utc(2026, 10).millisecondsSinceEpoch;

  late AppDatabase db;
  late DriftPeriodicalRepository rawPeriodicals;
  late DriftCatalogueItemRepository rawItems;
  late _IssuePeriodicals issuePeriodicals;
  late _IssueItems issueItems;
  late _CompetitorItems competitorItems;
  late _CompetitorPeriodicals competitorPeriodicals;
  late AddIssueUseCase addIssue;
  late UpdateIssueUseCase updateIssue;
  late UpdatePeriodicalUseCase updatePeriodical;
  late DeletePeriodicalUseCase deletePeriodical;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    rawPeriodicals = DriftPeriodicalRepository(db);
    rawItems = DriftCatalogueItemRepository(db);
    issueItems = _IssueItems(db);
    issuePeriodicals = _IssuePeriodicals(db, () => issueItems.depth);
    competitorItems = _CompetitorItems(db);
    competitorPeriodicals = _CompetitorPeriodicals(db);
    addIssue = AddIssueUseCase(
      periodicals: issuePeriodicals,
      items: issueItems,
    );
    updateIssue = UpdateIssueUseCase(
      periodicals: issuePeriodicals,
      items: issueItems,
    );
    updatePeriodical = UpdatePeriodicalUseCase(
      periodicals: rawPeriodicals,
      items: competitorItems,
    );
    deletePeriodical = DeletePeriodicalUseCase(
      periodicals: competitorPeriodicals,
    );
  });

  tearDown(() => db.close());

  T ok<T>(Either<Failure, T> result) =>
      result.getOrElse((failure) => fail('unexpected failure: $failure'));

  Failure failureOf<T>(Either<Failure, T> result) =>
      result.getLeft().toNullable() ?? fail('expected a failure, got $result');

  CatalogueItem draft(String periodicalUid, {int number = 1}) => CatalogueItem(
    title: '',
    addedDate: 1,
    details: IssueOf(
      periodicalUid: periodicalUid,
      issueNumber: number,
      issueDate: october2026,
    ),
  );

  Future<Periodical> seedSeries(String title) async => ok(
    await rawPeriodicals.insert(
      Periodical(
        title: title,
        titleTransliteration: '$title transliteration',
        publisher: '$title House',
        language: 'Telugu',
        ageGroup: AgeGroup.above6,
      ),
    ),
  );

  Future<CatalogueItem> seedIssue(Periodical series) async {
    final projected = IssueProjection.apply(
      draft(series.periodicalUid!),
      series,
    );
    return ok(await rawItems.insert(projected));
  }

  Periodical renamed(Periodical series) => series.copyWith(
    title: 'Renamed',
    titleTransliteration: 'Renamed transliteration',
    publisher: 'Renamed House',
    language: 'Hindi',
    ageGroup: AgeGroup.above10,
  );

  void expectProjection(CatalogueItem actual, Periodical series) {
    final expected = IssueProjection.apply(actual, series);
    expect(actual.title, expected.title);
    expect(actual.titleTransliteration, expected.titleTransliteration);
    expect(actual.publisher, expected.publisher);
    expect(actual.language, expected.language);
    expect(actual.publishedYear, expected.publishedYear);
    expect(actual.ageGroup, expected.ageGroup);
  }

  /// Start the competitor first and park it WITHOUT a database lock. Let the
  /// issue pass its captured series read and reach the REAL pre-write gate.
  /// Depth at THAT boundary selects only a deadlock-free schedule, never the
  /// expected result: a partial prepare-only transaction takes the legacy
  /// branch and exposes the later gap instead of passing falsely.
  Future<void> relay({
    required Future<void> Function() startCompetitor,
    required Future<void> Function() startIssue,
    required AsyncValueGate<void> beforeCompetitorWrite,
    required AsyncValueGate<void> afterSeriesLookup,
    required AsyncValueGate<void> beforeIssueWrite,
    required _IssueWrite write,
  }) async {
    issuePeriodicals.afterSeriesLookup = afterSeriesLookup;
    if (write == _IssueWrite.insert) {
      issueItems.beforeInsert = beforeIssueWrite;
    } else {
      issueItems.beforeUpdate = beforeIssueWrite;
    }
    final competitorFuture = startCompetitor();
    await beforeCompetitorWrite.entered;
    final issueFuture = startIssue();
    await afterSeriesLookup.entered;
    afterSeriesLookup.succeed(null);
    await beforeIssueWrite.entered;

    final writeDepth = write == _IssueWrite.insert
        ? issueItems.insertDepths.single
        : issueItems.updateDepths.single;
    if (writeDepth > 0) {
      beforeIssueWrite.succeed(null);
      await issueFuture;
      beforeCompetitorWrite.succeed(null);
      await competitorFuture;
    } else {
      beforeCompetitorWrite.succeed(null);
      await competitorFuture;
      beforeIssueWrite.succeed(null);
      await issueFuture;
    }
  }

  void expectWholeAddInTransaction() {
    expect(issueItems.transactionCalls, 1);
    expect(issuePeriodicals.seriesLookupDepths, [1]);
    expect(issuePeriodicals.identityLookupDepths, [1]);
    expect(issueItems.insertDepths, [1]);
  }

  void expectWholeUpdateInTransaction() {
    expect(issueItems.transactionCalls, 1);
    expect(issueItems.getByIdDepths, [1]);
    expect(issuePeriodicals.seriesLookupDepths, [1]);
    expect(issuePeriodicals.identityLookupDepths, [1]);
    expect(issueItems.updateDepths, [1]);
  }

  test('add then delete refuses deletion at the repository recount', () async {
    final series = await seedSeries('Original');
    final uid = series.periodicalUid!;
    final beforeDelete = AsyncValueGate<void>();
    final afterLookup = AsyncValueGate<void>();
    final beforeWrite = AsyncValueGate<void>();
    competitorPeriodicals.beforeDelete = beforeDelete;
    late Either<Failure, CatalogueItem> added;
    late Either<Failure, Unit> deletion;

    await relay(
      beforeCompetitorWrite: beforeDelete,
      afterSeriesLookup: afterLookup,
      beforeIssueWrite: beforeWrite,
      write: _IssueWrite.insert,
      startCompetitor: () async {
        deletion = await deletePeriodical(series.id);
      },
      startIssue: () async {
        added = await addIssue(draft(uid));
      },
    );

    expectWholeAddInTransaction();
    final storedSeries = ok(await rawPeriodicals.getById(series.id));
    final storedIssues = ok(await rawPeriodicals.issuesOf(uid));
    expect(storedSeries, isNotNull, reason: 'the add left an orphan behind');
    expect(storedIssues, hasLength(1));
    final saved = ok(added);
    final refusal = failureOf(deletion);
    expect(refusal, isA<PeriodicalHasIssuesFailure>());
    expect((refusal as PeriodicalHasIssuesFailure).issueCount, 1);
    expect(competitorPeriodicals.deleteCalls, 1);
    expect(storedIssues.single.id, saved.id);
    expectProjection(storedIssues.single, storedSeries!);
  });

  test(
    'add then rename reprojects the new issue from the committed series',
    () async {
      final series = await seedSeries('Original');
      final uid = series.periodicalUid!;
      final beforeRename = AsyncValueGate<void>();
      final afterLookup = AsyncValueGate<void>();
      final beforeWrite = AsyncValueGate<void>();
      competitorItems.beforeTransaction = beforeRename;
      late Either<Failure, CatalogueItem> added;
      late Either<Failure, Periodical> rename;

      await relay(
        beforeCompetitorWrite: beforeRename,
        afterSeriesLookup: afterLookup,
        beforeIssueWrite: beforeWrite,
        write: _IssueWrite.insert,
        startCompetitor: () async {
          rename = await updatePeriodical(renamed(series));
        },
        startIssue: () async {
          added = await addIssue(draft(uid));
        },
      );

      expectWholeAddInTransaction();
      final saved = ok(added);
      ok(rename);
      final storedSeries = ok(await rawPeriodicals.getById(series.id))!;
      final storedIssue = ok(await rawItems.getById(saved.id))!;
      expect(storedSeries.title, 'Renamed');
      expect(storedIssue.title, 'Renamed — No 1 (Oct 2026)');
      expect(storedIssue.publisher, 'Renamed House');
      expectProjection(storedIssue, storedSeries);
    },
  );

  test(
    'update then rename preserves the edit and the committed projection',
    () async {
      final series = await seedSeries('Original');
      final stored = await seedIssue(series);
      final beforeRename = AsyncValueGate<void>();
      final afterLookup = AsyncValueGate<void>();
      final beforeWrite = AsyncValueGate<void>();
      competitorItems.beforeTransaction = beforeRename;
      late Either<Failure, CatalogueItem> updated;
      late Either<Failure, Periodical> rename;

      await relay(
        beforeCompetitorWrite: beforeRename,
        afterSeriesLookup: afterLookup,
        beforeIssueWrite: beforeWrite,
        write: _IssueWrite.update,
        startCompetitor: () async {
          rename = await updatePeriodical(renamed(series));
        },
        startIssue: () async {
          updated = await updateIssue(stored.copyWith(notes: 'edited'));
        },
      );

      expectWholeUpdateInTransaction();
      final saved = ok(updated);
      ok(rename);
      final storedSeries = ok(await rawPeriodicals.getById(series.id))!;
      final storedIssue = ok(await rawItems.getById(stored.id))!;
      expect(storedIssue.id, stored.id);
      expect(storedIssue.itemUid, stored.itemUid);
      expect(storedIssue.notes, 'edited');
      expect(saved.id, stored.id);
      expect(storedSeries.title, 'Renamed');
      expect(storedIssue.title, 'Renamed — No 1 (Oct 2026)');
      expect(storedIssue.publisher, 'Renamed House');
      expectProjection(storedIssue, storedSeries);
    },
  );

  test('move then destination delete cannot orphan the moved issue', () async {
    final source = await seedSeries('Source');
    final target = await seedSeries('Target');
    final sourceUid = source.periodicalUid!;
    final targetUid = target.periodicalUid!;
    final stored = await seedIssue(source);
    final beforeDelete = AsyncValueGate<void>();
    final afterLookup = AsyncValueGate<void>();
    final beforeWrite = AsyncValueGate<void>();
    competitorPeriodicals.beforeDelete = beforeDelete;
    late Either<Failure, CatalogueItem> updated;
    late Either<Failure, Unit> deletion;

    await relay(
      beforeCompetitorWrite: beforeDelete,
      afterSeriesLookup: afterLookup,
      beforeIssueWrite: beforeWrite,
      write: _IssueWrite.update,
      startCompetitor: () async {
        deletion = await deletePeriodical(target.id);
      },
      startIssue: () async {
        updated = await updateIssue(
          stored.copyWith(
            notes: 'edited',
            details: IssueOf(
              periodicalUid: targetUid,
              issueNumber: 2,
              issueDate: october2026,
            ),
          ),
        );
      },
    );

    expectWholeUpdateInTransaction();
    final storedTarget = ok(await rawPeriodicals.getById(target.id));
    final targetIssues = ok(await rawPeriodicals.issuesOf(targetUid));
    expect(
      storedTarget,
      isNotNull,
      reason: 'the move attached to a deleted series',
    );
    expect(targetIssues, hasLength(1));
    final moved = ok(updated);
    final refusal = failureOf(deletion);
    expect(refusal, isA<PeriodicalHasIssuesFailure>());
    expect((refusal as PeriodicalHasIssuesFailure).issueCount, 1);
    expect(competitorPeriodicals.deleteCalls, 1);
    expect(ok(await rawPeriodicals.countIssues(sourceUid)), 0);
    expect(ok(await rawPeriodicals.countIssues(targetUid)), 1);
    expect(targetIssues.single.id, stored.id);
    expect(targetIssues.single.itemUid, stored.itemUid);
    expect(targetIssues.single.notes, 'edited');
    expect(moved.issue?.periodicalUid, targetUid);
    expect(targetIssues.single.title, 'Target — No 2 (Oct 2026)');
    expectProjection(targetIssues.single, storedTarget!);
  });
}
