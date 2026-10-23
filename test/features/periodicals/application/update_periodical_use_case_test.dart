import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/update_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/infrastructure/drift_periodical_repository.dart';

import 'periodical_fakes.dart';

/// `UpdatePeriodicalUseCase` (plan S12; ADR 0013 D3, D7): the gate and the
/// ISSN pre-check, then the series edit plus the re-projection of every
/// issue inside ONE transaction — proven first against the fakes (every
/// path, the mid-way failure) and then against the real Drift database
/// (the rollback itself).
void main() {
  // Valid ISSNs (mod-11 check digit): 0317-8471, 1234-5679.
  const issnA = '0317-8471';
  const issnB = '1234-5679';
  final oct2026 = DateTime(2026, 10).millisecondsSinceEpoch;

  group('with fakes', () {
    late FakePeriodicals periodicals;
    late FakeItems items;
    late UpdatePeriodicalUseCase useCase;

    setUp(() {
      periodicals = FakePeriodicals();
      items = FakeItems();
      useCase = UpdatePeriodicalUseCase(periodicals: periodicals, items: items);
    });

    /// An issue of the series [uid], stored in the item fake and listed by
    /// the periodical fake (what `issuesOf` answers).
    CatalogueItem seedIssue(
      String uid, {
      required String title,
      int? volume,
      int? number,
      int? date,
      int? until,
      String? transliteration,
      String? publisher,
      String? language,
    }) {
      final row = items.seed(
        CatalogueItem(
          title: title,
          titleTransliteration: transliteration,
          publisher: publisher,
          language: language,
          notes: 'own notes',
          copyCount: 2,
          addedDate: 1,
          details: IssueOf(
            periodicalUid: uid,
            volume: volume,
            issueNumber: number,
            issueDate: date,
            boundUntil: until,
          ),
        ),
      );
      periodicals.issues.putIfAbsent(uid, () => []).add(row);
      return row;
    }

    test(
      'an unpersisted periodical (emptyId) is NotFound; no store access',
      () async {
        final failure = failureOf(
          await useCase(const Periodical(title: 'Chandamama')),
        );
        expect(failure, isA<NotFoundFailure>());
        expect(periodicals.calls, isEmpty);
        expect(items.transactions, 0);
      },
    );

    test(
      'a blank title is a ValidationFailure; no transaction opened',
      () async {
        final stored = periodicals.seed(const Periodical(title: 'Chandamama'));
        final failure = failureOf(await useCase(stored.copyWith(title: ' ')));
        expect(failure, isA<ValidationFailure>());
        expect(items.transactions, 0);
        expect(periodicals.rows[stored.id]?.title, 'Chandamama');
      },
    );

    test("moving onto ANOTHER title's ISSN is DuplicateIssnFailure", () async {
      final other = periodicals.seed(const Periodical(title: 'A', issn: issnA));
      final mine = periodicals.seed(const Periodical(title: 'B', issn: issnB));
      final failure = failureOf(await useCase(mine.copyWith(issn: issnA)));
      expect(failure, isA<DuplicateIssnFailure>());
      failure as DuplicateIssnFailure;
      expect(failure.existingTitle, 'A');
      expect(failure.existingPeriodicalId, other.id);
      expect(items.transactions, 0);
      expect(periodicals.rows[mine.id]?.issn, issnB, reason: 'unchanged');
    });

    test('keeping your own ISSN is no collision', () async {
      final mine = periodicals.seed(const Periodical(title: 'B', issn: issnB));
      final saved = ok(await useCase(mine.copyWith(title: 'B renamed')));
      expect(saved.title, 'B renamed');
      expect(saved.issn, issnB);
    });

    test('a failed ISSN lookup aborts the edit (fail closed)', () async {
      final mine = periodicals.seed(const Periodical(title: 'B', issn: issnB));
      periodicals.findByIssnFailure = const StorageFailure('db closed');
      final failure = failureOf(await useCase(mine.copyWith(title: 'X')));
      expect(failure, isA<StorageFailure>());
      expect(items.transactions, 0);
      expect(periodicals.rows[mine.id]?.title, 'B');
    });

    test('a vanished row is NotFound and the transaction rolls back', () async {
      final failure = failureOf(
        await useCase(const Periodical(id: 404, title: 'Ghost')),
      );
      expect(failure, isA<NotFoundFailure>());
      expect(items.transactions, 1);
      expect(items.rolledBack, isTrue);
    });

    test(
      're-projects every issue of the series inside one transaction',
      () async {
        final series = periodicals.seed(
          const Periodical(
            title: 'Chandamama',
            titleTransliteration: 'Chandamama',
            publisher: 'Old House',
            language: 'Telugu',
          ),
        );
        final uid = series.periodicalUid!;
        final single = seedIssue(
          uid,
          title: 'Chandamama — Vol 2 No 1 (Oct 2026)',
          transliteration: 'Chandamama — Vol 2 No 1 (Oct 2026)',
          publisher: 'Old House',
          language: 'Telugu',
          volume: 2,
          number: 1,
          date: oct2026,
        );
        final bound = seedIssue(
          uid,
          title: 'Chandamama — Oct 2026 – Oct 2026',
          publisher: 'Old House',
          language: 'Telugu',
          date: oct2026,
          until: oct2026,
        );
        // An unrelated book never enters the picture.
        final book = items.seed(const CatalogueItem(title: 'A novel'));

        final edited = series.copyWith(
          title: 'Chandamama Classics',
          publisher: 'New House',
          language: 'Tamil',
          ageGroup: AgeGroup.above6,
        );
        final saved = ok(await useCase(edited));
        expect(saved.title, 'Chandamama Classics');
        expect(saved.periodicalUid, uid, reason: 'the stored uid wins');

        expect(items.transactions, 1);
        expect(items.rolledBack, isFalse);
        expect(
          items.calls.where((c) => c.startsWith('update')),
          everyElement('update(in transaction)'),
        );
        expect(
          periodicals.calls,
          containsAllInOrder(['update', 'issuesOf']),
          reason: 'the series row is written before its issues are re-read',
        );

        final newSingle = items.rows[single.id]!;
        expect(newSingle.title, 'Chandamama Classics — Vol 2 No 1 (Oct 2026)');
        expect(
          newSingle.titleTransliteration,
          'Chandamama — Vol 2 No 1 (Oct 2026)',
          reason: 'the series transliteration was not edited',
        );
        expect(newSingle.publisher, 'New House');
        expect(newSingle.language, 'Tamil');
        expect(newSingle.publishedYear, 2026);
        expect(newSingle.ageGroup, AgeGroup.above6);
        // The issue's own fields survive the rewrite.
        expect(newSingle.notes, 'own notes');
        expect(newSingle.copyCount, 2);
        expect(newSingle.issue?.issueNumber, 1);
        expect(newSingle.itemUid, single.itemUid);

        final newBound = items.rows[bound.id]!;
        expect(newBound.title, 'Chandamama Classics — Oct 2026 – Oct 2026');
        expect(
          newBound.titleTransliteration,
          'Chandamama — Oct 2026 – Oct 2026',
          reason: 'composed from the series transliteration, now filled in',
        );
        expect(newBound.issue?.isBound, isTrue);

        expect(items.rows[book.id], same(book), reason: 'untouched');
      },
    );

    test('editing a private field rewrites no issue at all', () async {
      final series = periodicals.seed(
        const Periodical(title: 'Chandamama', publisher: 'House'),
      );
      final uid = series.periodicalUid!;
      // Already projected exactly as the series says.
      seedIssue(uid, title: 'Chandamama — No 7', publisher: 'House', number: 7);
      final saved = ok(
        await useCase(
          series.copyWith(notes: 'renewed', subscriptionEnd: 99_999),
        ),
      );
      expect(saved.notes, 'renewed');
      expect(items.updated, isEmpty, reason: 'nothing to re-project');
      expect(items.transactions, 1);
    });

    test(
      'a mid-way failure rolls back the series edit and every issue',
      () async {
        final series = periodicals.seed(const Periodical(title: 'Old'));
        final uid = series.periodicalUid!;
        final first = seedIssue(uid, title: 'Old — No 1', number: 1);
        seedIssue(uid, title: 'Old — No 2', number: 2);
        seedIssue(uid, title: 'Old — No 3', number: 3);
        items
          ..failUpdateAt = 2
          ..updateFailure = const StorageFailure('disk full');

        final failure = failureOf(await useCase(series.copyWith(title: 'New')));
        expect(failure, isA<StorageFailure>());
        expect((failure as StorageFailure).reason, 'disk full');

        expect(items.updated, hasLength(2), reason: 'stopped at the failure');
        expect(items.rolledBack, isTrue);
        expect(items.rows[first.id]?.title, 'Old — No 1', reason: 'undone');
        // The series row itself was written inside the same transaction, so
        // the real database rolls it back too (see the Drift group below).
        expect(periodicals.calls, containsAllInOrder(['update', 'issuesOf']));
      },
    );

    test('a failed issue read rolls back the series edit', () async {
      final series = periodicals.seed(const Periodical(title: 'Old'));
      periodicals.issuesOfFailure = const StorageFailure('db closed');
      final failure = failureOf(await useCase(series.copyWith(title: 'New')));
      expect(failure, isA<StorageFailure>());
      expect(items.rolledBack, isTrue);
      expect(items.updated, isEmpty);
    });

    test('a projected issue that fails the gate refuses the edit', () async {
      final series = periodicals.seed(const Periodical(title: 'Old'));
      seedIssue(series.periodicalUid!, title: 'Old — No 1', number: 1);
      // At the cap the series title is valid, but "<title> — No 1" is not.
      final atTheCap = 'x' * CatalogueRules.maxFieldChars;
      final failure = failureOf(
        await useCase(series.copyWith(title: atTheCap)),
      );
      expect(failure, isA<ValidationFailure>());
      expect(
        (failure as ValidationFailure).message,
        'A title must be at most ${CatalogueRules.maxFieldChars} characters.',
      );
      expect(items.updated, isEmpty, reason: 'refused before the write');
      expect(items.rolledBack, isTrue);
    });
  });

  group('against Drift (the rollback is real)', () {
    late AppDatabase db;
    late DriftPeriodicalRepository periodicals;
    late DriftCatalogueItemRepository items;
    late UpdatePeriodicalUseCase useCase;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      periodicals = DriftPeriodicalRepository(db);
      items = DriftCatalogueItemRepository(db);
      useCase = UpdatePeriodicalUseCase(periodicals: periodicals, items: items);
    });

    tearDown(() => db.close());

    Future<CatalogueItem> addIssue(String uid, {required int number}) async =>
        ok(
          await items.insert(
            CatalogueItem(
              title: 'Chandamama — No $number',
              publisher: 'House',
              addedDate: 1,
              details: IssueOf(periodicalUid: uid, issueNumber: number),
            ),
          ),
        );

    test('a rename rewrites the issues and commits together', () async {
      final series = ok(
        await periodicals.insert(
          const Periodical(title: 'Chandamama', publisher: 'House'),
        ),
      );
      final uid = series.periodicalUid!;
      final one = await addIssue(uid, number: 1);
      final two = await addIssue(uid, number: 2);
      final book = ok(await items.insert(const CatalogueItem(title: 'Book')));

      ok(await useCase(series.copyWith(title: 'Chandamama Classics')));

      expect(
        ok(await periodicals.getById(series.id))?.title,
        'Chandamama Classics',
      );
      expect(
        ok(await items.getById(one.id))?.title,
        'Chandamama Classics — No 1',
      );
      expect(
        ok(await items.getById(two.id))?.title,
        'Chandamama Classics — No 2',
      );
      expect(ok(await items.getById(book.id))?.title, 'Book');
      expect(ok(await items.getById(one.id))?.itemUid, one.itemUid);
    });

    test('a failure after the series row was written rolls it back', () async {
      final series = ok(
        await periodicals.insert(const Periodical(title: 'Chandamama')),
      );
      final uid = series.periodicalUid!;
      final one = await addIssue(uid, number: 1);
      // The series row update succeeds (the title is within the cap); the
      // issue's composed title is over it, so the callback answers `Left`
      // and Drift must undo the series write it already performed.
      final atTheCap = 'x' * CatalogueRules.maxFieldChars;

      final failure = failureOf(
        await useCase(series.copyWith(title: atTheCap)),
      );
      expect(failure, isA<ValidationFailure>());

      expect(
        ok(await periodicals.getById(series.id))?.title,
        'Chandamama',
        reason: 'the series edit was rolled back',
      );
      expect(ok(await items.getById(one.id))?.title, 'Chandamama — No 1');
    });
  });
}
