import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/issue_sorter.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

import '../../support/raw_catalogue_rows.dart';

/// Item kinds through the repository (ADR 0013 F4/F6, D6; plan S10): the
/// detail row lives and dies with its base row, the kind and series facets
/// narrow BOTH reads (typed list and FTS search), the series order equals
/// `IssueSorter`, identity-key races surface as typed failures, and a row
/// from a newer build is read as a book but never written back.
void main() {
  late AppDatabase db;
  late DriftCatalogueItemRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftCatalogueItemRepository(db);
  });

  tearDown(() => db.close());

  T ok<T>(Either<Failure, T> e) =>
      e.getOrElse((f) => fail('unexpected failure: $f'));

  Future<List<CatalogueItem>> all(LibraryQuery q) async =>
      ok<CatalogueItemPage>(await repo.page(q, limit: 100)).items;

  LibraryQuery query({
    String text = '',
    ItemKind? kind,
    String? periodicalUid,
  }) => LibraryQuery(
    sort: LibrarySort.recentlyAdded,
    text: text,
    kind: kind,
    periodicalUid: periodicalUid,
  );

  CatalogueItem issue(
    String title, {
    String series = 'p-1',
    int? volume,
    int? number,
    int? date,
    int? until,
    String? label,
    int addedDate = 1,
  }) => CatalogueItem(
    title: title,
    addedDate: addedDate,
    details: IssueOf(
      periodicalUid: series,
      volume: volume,
      issueNumber: number,
      issueDate: date,
      boundUntil: until,
      label: label,
    ),
  );

  Future<List<int>> detailIds() async =>
      (await db.select(db.magazineIssues).get()).map((d) => d.itemId).toList();

  group('detail row lifecycle', () {
    test('an issue round-trips with its details; a book has none', () async {
      final saved = ok(
        await repo.insert(
          issue(
            'Chandamama — Vol 2 No 7 (Oct 2026)',
            volume: 2,
            number: 7,
            date: 1000,
            label: 'Dasara',
          ),
        ),
      );
      expect(saved.kind, ItemKind.magazineIssue);
      final read = ok(await repo.getById(saved.id))!;
      expect(read.kind, ItemKind.magazineIssue);
      expect(read.issue!.sameAs(saved.issue), isTrue);
      expect(read.issue!.label, 'Dasara');
      expect(await detailIds(), [saved.id]);

      final book = ok(await repo.insert(const CatalogueItem(title: 'Godaan')));
      expect(ok(await repo.getById(book.id))!.kind, ItemKind.book);
      expect(ok(await repo.getById(book.id))!.details, isNull);
      expect(await detailIds(), [saved.id]);
    });

    test('an Other item round-trips with the kind only', () async {
      final saved = ok(
        await repo.insert(
          const CatalogueItem(
            title: 'Carrom board',
            notes: 'wooden, 29 inch',
            details: OtherItemOf(),
          ),
        ),
      );
      final read = ok(await repo.getById(saved.id))!;
      expect(read.kind, ItemKind.other);
      expect(read.details, isA<OtherItemOf>());
      expect(read.notes, 'wooden, 29 inch');
      expect(await detailIds(), isEmpty);
      final stored = await (db.select(
        db.books,
      )..where((t) => t.id.equals(saved.id))).getSingle();
      expect(stored.kind, 'other');
    });

    test('update rewrites the detail row in place', () async {
      final saved = ok(await repo.insert(issue('No 1', number: 1)));
      final edited = ok(
        await repo.update(
          saved.copyWith(details: saved.issue!.copyWith(issueNumber: 2)),
        ),
      );
      expect(edited.issue!.issueNumber, 2);
      expect(ok(await repo.getById(saved.id))!.issue!.issueNumber, 2);
      expect(await detailIds(), [saved.id]);
    });

    test('a plain-item edit leaves no detail row behind', () async {
      final book = ok(await repo.insert(const CatalogueItem(title: 'B')));
      ok(await repo.update(book.copyWith(title: 'B2')));
      expect(await detailIds(), isEmpty);
      expect(ok(await repo.getById(book.id))!.title, 'B2');
    });

    test('deleting the base row cascades to the detail row', () async {
      final saved = ok(await repo.insert(issue('No 1', number: 1)));
      ok(await repo.delete(saved.id));
      expect(await detailIds(), isEmpty);
    });

    test('insertAll and replaceAll write details for every kind', () async {
      ok(
        await repo.insertAll([
          const CatalogueItem(title: 'book'),
          issue('issue', number: 1),
          const CatalogueItem(title: 'other', details: OtherItemOf()),
        ]),
      );
      final kinds = (await all(query())).map((i) => i.kind).toSet();
      expect(kinds, ItemKind.values.toSet());
      expect(await detailIds(), hasLength(1));

      ok(
        await repo.replaceAll([
          issue('issue A', number: 1),
          issue('issue B', number: 2),
        ]),
      );
      final after = await all(query());
      expect(
        after.map((i) => i.title),
        unorderedEquals(['issue A', 'issue B']),
      );
      expect(after.every((i) => i.issue != null), isTrue);
      expect(await detailIds(), hasLength(2), reason: 'old details cascaded');
    });
  });

  group('facets', () {
    setUp(() async {
      ok(
        await repo.insertAll([
          const CatalogueItem(
            title: 'probe book',
            notes: 'zebra',
            addedDate: 5,
          ),
          issue('probe issue', number: 1, addedDate: 4),
          const CatalogueItem(
            title: 'probe other',
            notes: 'carrom zebra',
            details: OtherItemOf(),
            addedDate: 3,
          ),
          issue('probe other series', series: 'p-2', number: 1, addedDate: 2),
        ]),
      );
    });

    test('kind narrows the typed list and the FTS search alike', () async {
      for (final kind in ItemKind.values) {
        final listed = await all(query(kind: kind));
        final searched = await all(query(text: 'probe', kind: kind));
        expect(listed.every((i) => i.kind == kind), isTrue, reason: '$kind');
        expect(
          searched.map((i) => i.title),
          listed.map((i) => i.title),
          reason: 'search and list agree for $kind',
        );
      }
      expect((await all(query(kind: ItemKind.magazineIssue))).length, 2);
      expect(
        (await all(query(kind: ItemKind.other))).single.title,
        'probe other',
      );
      expect((await all(query())).length, 4, reason: 'no chip = every kind');
    });

    test('series narrows to one periodical in both reads', () async {
      expect(
        (await all(query(periodicalUid: 'p-2'))).single.title,
        'probe other series',
      );
      expect(
        (await all(query(text: 'probe', periodicalUid: 'p-1'))).single.title,
        'probe issue',
      );
      expect(await all(query(periodicalUid: 'nope')), isEmpty);
    });

    test('search finds a word that lives only in the notes (D10)', () async {
      final hits = await all(query(text: 'zebra'));
      expect(
        hits.map((i) => i.title),
        unorderedEquals(['probe book', 'probe other']),
      );
      expect(
        (await all(query(text: 'zebra', kind: ItemKind.other))).single.title,
        'probe other',
      );
    });
  });

  group('series order == IssueSorter (both reads, across page seams)', () {
    test('date desc, volume desc, number desc, id desc; nulls last', () async {
      final rows = <CatalogueItem>[
        issue('probe a', date: 100, volume: 1, number: 2),
        issue('probe b', date: 300),
        issue('probe c', date: 100, volume: 2, number: 1),
        issue('probe d'),
        issue('probe e', date: 100, volume: 1, number: 3),
        // Same date and volume, no number: sorts after e and a (nulls last).
        issue('probe f', date: 100, volume: 1),
        issue('probe g', date: 200, until: 250),
        // No volume: after every volume at date 100.
        issue('probe h', date: 100, number: 9),
        issue('probe i', series: 'p-2', date: 999, number: 1),
        // Ties with d on every key: id desc puts this later row first.
        issue('probe j'),
      ];
      ok(await repo.insertAll(rows));
      final stored = ok(
        await repo.getAll(),
      ).where((i) => i.issue!.periodicalUid == 'p-1').toList();
      final expected = IssueSorter.sort(stored).map((i) => i.title).toList();

      Future<List<String>> paged(LibraryQuery q) async {
        final out = <CatalogueItem>[];
        var page = ok(await repo.page(q, limit: 3));
        out.addAll(page.items);
        while (page.hasMore) {
          page = ok(await repo.page(q, limit: 3, offset: out.length));
          out.addAll(page.items);
        }
        return out.map((i) => i.title).toList();
      }

      expect(await paged(query(periodicalUid: 'p-1')), expected);
      expect(await paged(query(text: 'probe', periodicalUid: 'p-1')), expected);
      expect(expected.first, 'probe b');
      expect(expected.sublist(expected.length - 2), ['probe j', 'probe d']);
    });
  });

  group('identity keys (D6) — races surface as DuplicateIssueFailure', () {
    test('the same (series, volume-or-0, number) twice', () async {
      final first = ok(await repo.insert(issue('No 4', number: 4)));
      final r = await repo.insert(issue('No 4 again', volume: 0, number: 4));
      final failure = r.getLeft().toNullable();
      expect(failure, isA<DuplicateIssueFailure>());
      final dup = failure! as DuplicateIssueFailure;
      expect(dup.existingItemId, first.id);
      expect(dup.existingTitle, 'No 4');
      // A different volume, or a different series, is a different issue.
      expect(
        (await repo.insert(issue('v2 no 4', volume: 2, number: 4))).isRight(),
        isTrue,
      );
      expect(
        (await repo.insert(
          issue('p2 no 4', series: 'p-2', number: 4),
        )).isRight(),
        isTrue,
      );
    });

    test(
      'the same bound range twice; an update onto another row too',
      () async {
        final first = ok(
          await repo.insert(issue('bound', date: 10, until: 20)),
        );
        final r = await repo.insert(issue('bound again', date: 10, until: 20));
        expect(r.getLeft().toNullable(), isA<DuplicateIssueFailure>());
        final other = ok(
          await repo.insert(issue('bound 2', date: 30, until: 40)),
        );
        final moved = await repo.update(
          other.copyWith(
            details: other.issue!.copyWith(issueDate: 10, boundUntil: 20),
          ),
        );
        final dup = moved.getLeft().toNullable()! as DuplicateIssueFailure;
        expect(dup.existingItemId, first.id);
        // Keeping your own key is no collision.
        expect(
          (await repo.update(first.copyWith(title: 'bound!'))).isRight(),
          isTrue,
        );
      },
    );
  });

  group('unknown kind token (F6)', () {
    test('reads as a book, is refused on write-back, deletes fine', () async {
      final id = await seedRawCatalogueRow(
        db,
        title: 'from the future',
        kind: 'hologram',
      );
      final read = ok(await repo.getById(id))!;
      expect(read.kind, ItemKind.book);
      expect(read.details, isNull);
      expect((await all(query())).single.title, 'from the future');
      expect(ok(await repo.getAll()).single.kind, ItemKind.book);
      final strict = await repo.getAllForInterchange();
      expect(strict.getLeft().toNullable(), isA<UnsupportedItemKindFailure>());

      final r = await repo.update(read.copyWith(title: 'renamed'));
      final failure = r.getLeft().toNullable();
      expect(failure, isA<UnsupportedItemKindFailure>());
      expect((failure! as UnsupportedItemKindFailure).kindToken, 'hologram');
      final stored = await (db.select(
        db.books,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(stored.kind, 'hologram', reason: 'stored token untouched');
      expect(stored.title, 'from the future');

      ok(await repo.markRemoved(id, 99));
      ok(await repo.delete(id));
      expect(await all(query()), isEmpty);
    });

    test('an issue row that lost its detail row reads as a book', () async {
      final id = await seedRawCatalogueRow(
        db,
        title: 'orphan',
        kind: 'magazine-issue',
      );
      final read = ok(await repo.getById(id))!;
      expect(read.kind, ItemKind.book);
      expect(ok(await repo.getAll()).single.kind, ItemKind.book);
      final strict = await repo.getAllForInterchange();
      expect(strict.getLeft().toNullable(), isA<StorageFailure>());
    });

    test(
      'a detail-less issue refuses write-back and preserves raw evidence',
      () async {
        final id = await seedRawCatalogueRow(
          db,
          title: 'raw issue title',
          kind: 'magazine-issue',
          coverUrl: 'covers/raw.jpg',
        );
        final display = ok(await repo.getById(id))!;
        expect(display.kind, ItemKind.book);

        final result = await repo.update(
          display.copyWith(title: 'replacement', coverUrl: 'covers/new.jpg'),
        );
        expect(result.getLeft().toNullable(), isA<StorageFailure>());
        final stored = await (db.select(
          db.books,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(stored.kind, 'magazine-issue');
        expect(stored.title, 'raw issue title');
        expect(stored.coverUrl, 'covers/raw.jpg');
      },
    );
  });
}
