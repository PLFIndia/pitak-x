import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_sorter.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/infrastructure/drift_periodical_repository.dart';

/// The periodicals store through its repository (ADR 0013 D2, D6, D7, D8;
/// plan S11): uid minting and preservation, the ISSN race net, the
/// fail-closed delete, the one-statement Magazines summary in its documented
/// order, and the series-side issue reads that must agree with the item
/// repository's identity key and `IssueSorter`.
void main() {
  const day1 = 1735689600000; // 2025-01-01T00:00:00Z
  const day2 = 1735776000000; // 2025-01-02T00:00:00Z
  const day3 = 1735862400000; // 2025-01-03T00:00:00Z
  const day4 = 1735948800000; // 2025-01-04T00:00:00Z
  const day5 = 1736035200000; // 2025-01-05T00:00:00Z

  late AppDatabase db;
  late DriftPeriodicalRepository repo;
  late DriftCatalogueItemRepository items;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftPeriodicalRepository(db);
    items = DriftCatalogueItemRepository(db);
  });

  tearDown(() => db.close());

  T ok<T>(Either<Failure, T> e) =>
      e.getOrElse((f) => fail('unexpected failure: $f'));

  Failure failureOf<T>(Either<Failure, T> e) =>
      e.getLeft().toNullable() ?? fail('expected a failure, got $e');

  // Valid ISSNs (mod-11 check digit): 0317-8471, 1234-5679, 2434-561X.
  const issnA = '0317-8471';
  const issnB = '1234-5679';
  const issnX = '2434-561X';

  const full = Periodical(
    periodicalUid: 'uid-full',
    title: 'Chandamama',
    titleTransliteration: 'Chandamama',
    issn: issnA,
    publisher: 'Chandamama Publications',
    language: 'Telugu',
    coverUrl: 'covers/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg',
    frequency: PeriodicalFrequency.monthly,
    subscriptionStart: day1,
    subscriptionEnd: day2,
    notes: 'private note',
    location: 'Shelf 3',
    sourceType: ItemSourceType.purchased,
    sourceDetail: 'Higginbothams',
    ageGroup: AgeGroup.above3,
    addedDate: 42,
    removed: true,
    removedAt: 99,
    addedBy: 'ravi',
  );

  /// An issue of [series] written through the ITEM repository — the real
  /// write path, so the detail row is exactly what production stores.
  Future<CatalogueItem> addIssue(
    String series, {
    String title = 'issue',
    int? volume,
    int? number,
    int? date,
    int? until,
  }) async => ok(
    await items.insert(
      CatalogueItem(
        title: title,
        addedDate: 1,
        details: IssueOf(
          periodicalUid: series,
          volume: volume,
          issueNumber: number,
          issueDate: date,
          boundUntil: until,
        ),
      ),
    ),
  );

  group('insert', () {
    test('mints a uid, assigns an id, round-trips every field', () async {
      final saved = ok(
        await repo.insert(const Periodical(title: 'Chandamama')),
      );
      expect(saved.id, isNot(Periodical.emptyId));
      expect(saved.periodicalUid, isNotNull);
      expect(saved.periodicalUid, hasLength(36), reason: 'a UUID v4');

      final rich = ok(await repo.insert(full));
      final read = ok(await repo.getById(rich.id))!;
      expect(read.sameAs(full), isTrue, reason: 'every column round-trips');
      expect(read.id, rich.id);
      expect(read.frequency, PeriodicalFrequency.monthly);
      expect(read.sourceType, ItemSourceType.purchased);
      expect(read.ageGroup, AgeGroup.above3);
    });

    test('keeps an incoming uid; a blank uid is minted fresh', () async {
      final kept = ok(
        await repo.insert(
          const Periodical(title: 'A', periodicalUid: 'imported-uid'),
        ),
      );
      expect(kept.periodicalUid, 'imported-uid');
      final minted = ok(
        await repo.insert(const Periodical(title: 'B', periodicalUid: '  ')),
      );
      expect(minted.periodicalUid, isNot('  '));
      expect(minted.periodicalUid!.trim(), isNotEmpty);
      expect(ok(await repo.findByUid('imported-uid'))!.id, kept.id);
    });

    test(
      'trims an incoming uid and refuses a trim-equivalent duplicate',
      () async {
        final saved = ok(
          await repo.insert(
            const Periodical(title: 'A', periodicalUid: '  p1  '),
          ),
        );
        expect(saved.periodicalUid, 'p1');
        final result = await repo.insert(
          const Periodical(title: 'B', periodicalUid: 'p1'),
        );
        expect(failureOf(result), isA<ValidationFailure>());
        final stored = await db.select(db.periodicals).get();
        expect(stored.single.title, 'A');
        expect(stored.single.periodicalUid, 'p1');
      },
    );

    test('a blank ISSN is stored as NULL, so two of them coexist', () async {
      ok(await repo.insert(const Periodical(title: 'A', issn: '')));
      ok(await repo.insert(const Periodical(title: 'B', issn: '   ')));
      final stored = await db.select(db.periodicals).get();
      expect(stored.map((r) => r.issn), [null, null]);
      expect(ok(await repo.findByIssn('')), isNull);
    });

    test('the same ISSN twice → DuplicateIssnFailure naming the row', () async {
      final first = ok(
        await repo.insert(const Periodical(title: 'First', issn: issnA)),
      );
      final r = await repo.insert(
        const Periodical(title: 'Again', issn: issnA),
      );
      final failure = failureOf(r);
      expect(failure, isA<DuplicateIssnFailure>());
      final dup = failure as DuplicateIssnFailure;
      expect(dup.existingTitle, 'First');
      expect(dup.existingPeriodicalId, first.id);
      expect(await db.select(db.periodicals).get(), hasLength(1));
      // A different ISSN is a different title.
      expect(
        (await repo.insert(
          const Periodical(title: 'Other', issn: issnB),
        )).isRight(),
        isTrue,
      );
    });
  });

  group('canonical soft links', () {
    test(
      'lookup, summary, issues, and delete guard share one trimmed key',
      () async {
        final saved = ok(
          await repo.insert(
            const Periodical(title: 'Frontline', periodicalUid: ' p1 '),
          ),
        );
        await addIssue('p1', number: 1);

        expect(ok(await repo.findByUid(' p1 '))!.id, saved.id);
        expect(ok(await repo.countIssues(' p1 ')), 1);
        expect(ok(await repo.issuesOf(' p1 ')), hasLength(1));
        final summary = ok(await repo.listAll()).single;
        expect(summary.issueCount, 1);
        expect(summary.latestIssueDate, isNull);
        expect(
          failureOf(await repo.delete(saved.id)),
          isA<PeriodicalHasIssuesFailure>(),
        );
      },
    );
  });

  group('lookups', () {
    test('getById / findByUid: missing → null, blank uid → null', () async {
      expect(ok(await repo.getById(404)), isNull);
      expect(ok(await repo.findByUid('')), isNull);
      expect(ok(await repo.findByUid('   ')), isNull);
      expect(ok(await repo.findByUid('nope')), isNull);
      final saved = ok(await repo.insert(const Periodical(title: 'A')));
      expect(ok(await repo.findByUid(saved.periodicalUid!))!.id, saved.id);
      expect(
        ok(await repo.findByUid(' ${saved.periodicalUid!} '))!.id,
        saved.id,
      );
    });

    test('findByIssn normalises its input; invalid matches nothing', () async {
      final saved = ok(
        await repo.insert(const Periodical(title: 'A', issn: issnA)),
      );
      final x = ok(
        await repo.insert(const Periodical(title: 'X', issn: issnX)),
      );
      for (final spelling in [issnA, '03178471', ' 0317 8471 ', '0317-8471']) {
        expect(
          ok(await repo.findByIssn(spelling))?.id,
          saved.id,
          reason: spelling,
        );
      }
      expect(ok(await repo.findByIssn('2434-561x'))?.id, x.id);
      expect(
        ok(await repo.findByIssn('0317-8472')),
        isNull,
        reason: 'bad check',
      );
      expect(ok(await repo.findByIssn('not an issn')), isNull);
      expect(ok(await repo.findByIssn(issnB)), isNull, reason: 'not stored');
    });

    test(
      'an unknown stored frequency token reads as null (tolerant)',
      () async {
        final id = await db
            .into(db.periodicals)
            .insert(
              PeriodicalsCompanion.insert(
                periodicalUid: 'u',
                title: 'From the future',
                addedDate: 1,
                frequency: const Value('decennial'),
              ),
            );
        final read = ok(await repo.getById(id))!;
        expect(read.frequency, isNull);
        expect(read.title, 'From the future');
      },
    );
  });

  group('update', () {
    test('an unsaved or missing row → NotFoundFailure', () async {
      expect(
        failureOf(await repo.update(const Periodical(title: 'x'))),
        isA<NotFoundFailure>(),
      );
      expect(
        failureOf(await repo.update(const Periodical(id: 77, title: 'x'))),
        isA<NotFoundFailure>(),
      );
    });

    test(
      'edits fields in place; id and the STORED uid are preserved',
      () async {
        final saved = ok(await repo.insert(const Periodical(title: 'A')));
        final uid = saved.periodicalUid!;

        final edited = ok(
          await repo.update(
            saved.copyWith(
              title: 'A renamed',
              frequency: PeriodicalFrequency.weekly,
              issn: issnA,
            ),
          ),
        );
        expect(edited.id, saved.id);
        expect(edited.periodicalUid, uid);
        final read = ok(await repo.getById(saved.id))!;
        expect(read.title, 'A renamed');
        expect(read.frequency, PeriodicalFrequency.weekly);
        expect(read.issn, issnA);

        // An incoming row that dropped its uid, or carries a DIFFERENT one
        // (an import), never rewrites the key every issue links to.
        final dropped = ok(
          await repo.update(Periodical(id: saved.id, title: 'no uid')),
        );
        expect(dropped.periodicalUid, uid);
        final foreign = ok(
          await repo.update(
            Periodical(id: saved.id, title: 'other uid', periodicalUid: 'zzz'),
          ),
        );
        expect(foreign.periodicalUid, uid);
        expect(ok(await repo.getById(saved.id))!.periodicalUid, uid);
        expect(ok(await repo.findByUid('zzz')), isNull);
      },
    );

    test(
      "moving onto another row's ISSN → DuplicateIssnFailure; own is fine",
      () async {
        final a = ok(
          await repo.insert(const Periodical(title: 'A', issn: issnA)),
        );
        final b = ok(
          await repo.insert(const Periodical(title: 'B', issn: issnB)),
        );

        final moved = await repo.update(b.copyWith(issn: issnA));
        final dup = failureOf(moved) as DuplicateIssnFailure;
        expect(dup.existingPeriodicalId, a.id);
        expect(dup.existingTitle, 'A');
        expect(ok(await repo.getById(b.id))!.issn, issnB, reason: 'untouched');

        // Keeping your own ISSN is no collision.
        expect((await repo.update(a.copyWith(title: 'A!'))).isRight(), isTrue);
        expect(ok(await repo.getById(a.id))!.title, 'A!');
      },
    );
  });

  group('soft remove / restore', () {
    test('markRemoved sets the flag and timestamp; restore clears', () async {
      final saved = ok(await repo.insert(const Periodical(title: 'A')));
      ok(await repo.markRemoved(saved.id, 1234));
      var read = ok(await repo.getById(saved.id))!;
      expect(read.removed, isTrue);
      expect(read.removedAt, 1234);
      ok(await repo.restoreRemoved(saved.id));
      read = ok(await repo.getById(saved.id))!;
      expect(read.removed, isFalse);
      expect(read.removedAt, isNull);
    });
  });

  group('delete (D8: fails closed while issues reference the series)', () {
    test('with no issues the row goes; a missing id is a no-op', () async {
      final saved = ok(await repo.insert(const Periodical(title: 'A')));
      ok(await repo.delete(saved.id));
      expect(ok(await repo.getById(saved.id)), isNull);
      expect((await repo.delete(saved.id)).isRight(), isTrue);
      expect((await repo.delete(404)).isRight(), isTrue);
    });

    test('with issues → PeriodicalHasIssuesFailure(count), row kept', () async {
      final saved = ok(await repo.insert(const Periodical(title: 'A')));
      final uid = saved.periodicalUid!;
      final one = await addIssue(uid, number: 1);
      final two = await addIssue(uid, number: 2);
      // A soft-removed issue still exists and still links to the series.
      ok(await items.markRemoved(two.id, 5));
      await addIssue('another-series', number: 1);

      final refused = failureOf(await repo.delete(saved.id));
      expect(refused, isA<PeriodicalHasIssuesFailure>());
      expect((refused as PeriodicalHasIssuesFailure).issueCount, 2);
      expect(ok(await repo.getById(saved.id)), isNotNull);

      // Soft-removing the series is always allowed (issues untouched).
      ok(await repo.markRemoved(saved.id, 9));
      expect(ok(await items.getById(one.id)), isNotNull);

      // Once the issues are gone, the hard delete succeeds.
      ok(await items.delete(one.id));
      ok(await items.delete(two.id));
      ok(await repo.delete(saved.id));
      expect(ok(await repo.getById(saved.id)), isNull);
    });
  });

  group('countIssues', () {
    test('counts the rows of that series only; blank → 0', () async {
      await addIssue('p-1', number: 1);
      await addIssue('p-1', number: 2);
      await addIssue('p-1', date: day1, until: day2);
      await addIssue('p-2', number: 1);
      expect(ok(await repo.countIssues('p-1')), 3);
      expect(ok(await repo.countIssues('p-2')), 1);
      expect(ok(await repo.countIssues('p-3')), 0);
      expect(ok(await repo.countIssues('')), 0);
      expect(ok(await repo.countIssues('  ')), 0);
    });
  });

  group('listAll', () {
    test('orders by title (code-unit) then id; every row included', () async {
      final b = ok(await repo.insert(const Periodical(title: 'b')));
      final upperB = ok(await repo.insert(const Periodical(title: 'B')));
      final a1 = ok(await repo.insert(const Periodical(title: 'a')));
      final a2 = ok(await repo.insert(const Periodical(title: 'a')));
      ok(await repo.markRemoved(b.id, 1)); // soft-removed titles still list
      final listed = ok(await repo.listAll());
      // SQLite's default BINARY collation: 'B' (0x42) < 'a' (0x61) < 'b'.
      expect(listed.map((s) => s.periodical.id), [
        upperB.id,
        a1.id,
        a2.id,
        b.id,
      ]);
      expect(listed.last.periodical.removed, isTrue);
    });

    test('summaries: count (removed included) and newest date', () async {
      final series = ok(await repo.insert(full.copyWith(removed: false)));
      final uid = series.periodicalUid!;
      final undated = ok(await repo.insert(const Periodical(title: 'Undated')));
      final empty = ok(await repo.insert(const Periodical(title: 'Zero')));

      await addIssue(uid, number: 1, date: day1);
      final newest = await addIssue(uid, number: 2, date: day4);
      await addIssue(uid, number: 3, date: day2);
      await addIssue(uid, date: day1, until: day2);
      ok(await items.markRemoved(newest.id, 7));
      await addIssue(undated.periodicalUid!, number: 1);

      final byId = {
        for (final s in ok(await repo.listAll())) s.periodical.id: s,
      };
      expect(byId, hasLength(3));
      expect(byId[series.id]!.issueCount, 4);
      expect(byId[series.id]!.latestIssueDate, day4, reason: 'removed counts');
      expect(byId[series.id]!.periodical.sameAs(series), isTrue);
      expect(byId[undated.id]!.issueCount, 1);
      expect(byId[undated.id]!.latestIssueDate, isNull);
      expect(byId[empty.id]!.issueCount, 0);
      expect(byId[empty.id]!.latestIssueDate, isNull);
    });

    test('an empty store lists nothing', () async {
      expect(ok(await repo.listAll()), isEmpty);
    });
  });

  group('findIssue (D6 numbered key: series, volume-or-0, number)', () {
    test('finds the row with its details; volume null ≡ 0', () async {
      final plain = await addIssue('p-1', title: 'No 4', number: 4);
      final vol2 = await addIssue(
        'p-1',
        title: 'V2 No 4',
        volume: 2,
        number: 4,
      );

      final found = ok(
        await repo.findIssue(
          periodicalUid: 'p-1',
          volume: null,
          issueNumber: 4,
        ),
      )!;
      expect(found.id, plain.id);
      expect(found.kind, ItemKind.magazineIssue);
      expect(found.issue!.sameAs(plain.issue), isTrue);
      expect(
        ok(
          await repo.findIssue(periodicalUid: 'p-1', volume: 0, issueNumber: 4),
        )!.id,
        plain.id,
        reason: 'COALESCE(volume, 0): a stored NULL volume matches 0',
      );
      expect(
        ok(
          await repo.findIssue(periodicalUid: 'p-1', volume: 2, issueNumber: 4),
        )!.id,
        vol2.id,
      );
    });

    test('excludes bound volumes, other series and other numbers', () async {
      await addIssue('p-1', number: 4, date: day1, until: day2); // bound, No 4
      await addIssue('p-2', number: 4);
      expect(
        ok(
          await repo.findIssue(
            periodicalUid: 'p-1',
            volume: null,
            issueNumber: 4,
          ),
        ),
        isNull,
        reason: 'a bound volume never answers the numbered key',
      );
      expect(
        ok(
          await repo.findIssue(
            periodicalUid: 'p-1',
            volume: null,
            issueNumber: 5,
          ),
        ),
        isNull,
      );
      expect(
        ok(
          await repo.findIssue(
            periodicalUid: 'p-9',
            volume: null,
            issueNumber: 4,
          ),
        ),
        isNull,
      );
    });
  });

  group('findBoundVolume (D6 bound key: series, first date, last date)', () {
    test('finds the exact range only', () async {
      final bound = await addIssue(
        'p-1',
        title: 'bound',
        date: day1,
        until: day2,
      );
      await addIssue('p-1', title: 'single', date: day1); // same first date
      await addIssue('p-2', date: day1, until: day2); // other series

      final found = ok(
        await repo.findBoundVolume(
          periodicalUid: 'p-1',
          issueDate: day1,
          boundUntil: day2,
        ),
      )!;
      expect(found.id, bound.id);
      expect(found.issue!.isBound, isTrue);
      expect(
        ok(
          await repo.findBoundVolume(
            periodicalUid: 'p-1',
            issueDate: day1,
            boundUntil: day3,
          ),
        ),
        isNull,
      );
      expect(
        ok(
          await repo.findBoundVolume(
            periodicalUid: 'p-3',
            issueDate: day1,
            boundUntil: day2,
          ),
        ),
        isNull,
      );
    });
  });

  group('issuesOf', () {
    test('every issue of the series in IssueSorter order', () async {
      await addIssue('p-1', title: 'a', date: day1, volume: 1, number: 2);
      await addIssue('p-1', title: 'b', date: day4);
      await addIssue('p-1', title: 'c', date: day1, volume: 2, number: 1);
      final d = await addIssue('p-1', title: 'd');
      await addIssue('p-1', title: 'e', date: day1, volume: 1, number: 3);
      await addIssue('p-1', title: 'f', date: day1, volume: 1);
      await addIssue('p-1', title: 'g', date: day2, until: day3);
      await addIssue('p-1', title: 'h', date: day1, number: 9);
      await addIssue('p-2', title: 'other series', date: day5, number: 1);
      await addIssue('p-1', title: 'j');
      ok(await items.markRemoved(d.id, 3)); // still an issue of p-1

      final stored = ok(
        await items.getAll(),
      ).where((i) => i.issue!.periodicalUid == 'p-1').toList();
      final expected = IssueSorter.sort(stored).map((i) => i.title).toList();

      final listed = ok(await repo.issuesOf('p-1'));
      expect(listed.map((i) => i.title), expected);
      expect(listed, hasLength(9));
      expect(listed.first.title, 'b');
      expect(listed.map((i) => i.title).toList().sublist(7), ['j', 'd']);
      expect(listed.every((i) => i.kind == ItemKind.magazineIssue), isTrue);
    });

    test('blank or unknown series → empty', () async {
      await addIssue('p-1', number: 1);
      expect(ok(await repo.issuesOf('')), isEmpty);
      expect(ok(await repo.issuesOf('  ')), isEmpty);
      expect(ok(await repo.issuesOf('p-9')), isEmpty);
    });
  });

  group('insertAll', () {
    test('returns every row with id and uid (kept or minted)', () async {
      final inserted = ok(
        await repo.insertAll(const [
          Periodical(title: 'A', periodicalUid: 'keep-me'),
          Periodical(title: 'B'),
        ]),
      );
      expect(inserted.map((p) => p.title), ['A', 'B']);
      expect(inserted[0].periodicalUid, 'keep-me');
      expect(inserted[1].periodicalUid, isNotNull);
      expect(inserted.map((p) => p.id).toSet(), hasLength(2));
      expect(inserted.every((p) => p.id != Periodical.emptyId), isTrue);
      expect(ok(await repo.listAll()), hasLength(2));
    });

    test(
      'is atomic: a duplicate ISSN inside the batch lands nothing',
      () async {
        ok(await repo.insert(const Periodical(title: 'kept')));
        final r = await repo.insertAll(const [
          Periodical(title: 'A', issn: issnA),
          Periodical(title: 'B', issn: issnA),
        ]);
        expect(failureOf(r), isA<StorageFailure>());
        final titles = ok(await repo.listAll()).map((s) => s.periodical.title);
        expect(titles, ['kept']);
      },
    );
  });

  group('replaceAll', () {
    test('replaces every row; keeps incoming uids, mints null ones', () async {
      ok(await repo.insert(const Periodical(title: 'old', issn: issnA)));
      final count = ok(
        await repo.replaceAll(const [
          Periodical(title: 'new 1', periodicalUid: 'u-1', issn: issnA),
          Periodical(title: 'new 2'),
        ]),
      );
      expect(count, 2);
      final listed = ok(await repo.listAll()).map((s) => s.periodical).toList();
      expect(listed.map((p) => p.title), ['new 1', 'new 2']);
      expect(listed[0].periodicalUid, 'u-1');
      expect(listed[1].periodicalUid, isNotNull);
      expect(ok(await repo.findByIssn(issnA))!.title, 'new 1');
    });

    test(
      'a trim-created collision is refused before deleting old rows',
      () async {
        ok(await repo.insert(const Periodical(title: 'old')));
        final result = await repo.replaceAll(const [
          Periodical(title: 'A', periodicalUid: 'p1'),
          Periodical(title: 'B', periodicalUid: ' p1 '),
        ]);
        expect(failureOf(result), isA<ValidationFailure>());
        final stored = ok(await repo.listAll());
        expect(stored.single.periodical.title, 'old');
      },
    );

    test('is atomic: a failing batch keeps the old rows', () async {
      ok(await repo.insert(const Periodical(title: 'old')));
      final r = await repo.replaceAll(const [
        Periodical(title: 'A', issn: issnB),
        Periodical(title: 'B', issn: issnB),
      ]);
      expect(failureOf(r), isA<StorageFailure>());
      final titles = ok(await repo.listAll()).map((s) => s.periodical.title);
      expect(titles, ['old']);
    });
  });
}
