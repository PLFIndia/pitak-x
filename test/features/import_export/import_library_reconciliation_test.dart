import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';
import 'package:pitaka/features/periodicals/infrastructure/drift_periodical_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';

import '../periodicals/application/periodical_fakes.dart' show FakeSettings;

String _json({
  int schemaVersion = 4,
  List<Map<String, dynamic>> periodicals = const [],
  List<Map<String, dynamic>> books = const [],
  List<Map<String, dynamic>> wishlist = const [],
}) => jsonEncode({
  'schemaVersion': schemaVersion,
  'exportedAt': 0,
  if (schemaVersion >= 4) 'periodicals': periodicals,
  'books': books,
  'wishlist': wishlist,
});

Map<String, dynamic> _series(
  String uid,
  String title, {
  String? issn,
  String? publisher,
  String? language,
  String? coverUrl,
  int? addedDate,
  String? addedBy,
}) => {
  'periodicalUid': uid,
  'title': title,
  if (issn != null) 'issn': issn,
  if (publisher != null) 'publisher': publisher,
  if (language != null) 'language': language,
  if (coverUrl != null) 'coverUrl': coverUrl,
  if (addedDate != null) 'addedDate': addedDate,
  if (addedBy != null) 'addedBy': addedBy,
};

Map<String, dynamic> _issue(
  String uid,
  String seriesUid, {
  int? volume,
  int? issueNumber,
  int? issueDate,
  int? boundUntil,
}) => {
  'bookUid': uid,
  'kind': 'magazine-issue',
  'title': 'Incoming issue',
  'issue': {
    'periodicalUid': seriesUid,
    if (volume != null) 'volume': volume,
    if (issueNumber != null) 'issueNumber': issueNumber,
    if (issueDate != null) 'issueDate': issueDate,
    if (boundUntil != null) 'boundUntil': boundUntil,
  },
};

Map<String, dynamic> _plainItem(String uid, ItemKind kind) => {
  'bookUid': uid,
  'title': 'Incoming ${kind.name}',
  'kind': switch (kind) {
    ItemKind.book => 'book',
    ItemKind.magazineIssue => 'magazine-issue',
    ItemKind.other => 'other',
  },
};

void main() {
  final january = DateTime.utc(2026, 1, 15).millisecondsSinceEpoch;
  final february = DateTime.utc(2026, 2, 15).millisecondsSinceEpoch;
  final march = DateTime.utc(2026, 3, 15).millisecondsSinceEpoch;

  late AppDatabase db;
  late DriftCatalogueItemRepository items;
  late DriftPeriodicalRepository periodicals;
  late DriftWishlistRepository wishlist;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    items = DriftCatalogueItemRepository(db);
    periodicals = DriftPeriodicalRepository(db);
    wishlist = DriftWishlistRepository(db);
  });

  tearDown(() async => db.close());

  T ok<T>(Either<Failure, T> result) =>
      result.getOrElse((failure) => fail('unexpected failure: $failure'));

  ImportLibraryUseCase useCase({CatalogueItemRepository? itemRepository}) =>
      ImportLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: itemRepository ?? items,
        wishlistRepo: wishlist,
        periodicalRepo: periodicals,
      );

  Future<List<CatalogueItem>> storedItems() async =>
      ok(await items.getAllForInterchange());

  Future<List<Periodical>> storedSeries() async => [
    for (final summary in ok(await periodicals.listAll())) summary.periodical,
  ];

  Future<Periodical> seedSeries(Periodical periodical) async =>
      ok(await periodicals.insert(periodical));

  Future<CatalogueItem> seedIssue(
    Periodical series,
    String uid, {
    int? volume,
    int? issueNumber,
    int? issueDate,
    int? boundUntil,
  }) async {
    final row = CatalogueItem(
      itemUid: uid,
      title: 'Unprojected',
      details: IssueOf(
        periodicalUid: series.periodicalUid!,
        volume: volume,
        issueNumber: issueNumber,
        issueDate: issueDate,
        boundUntil: boundUntil,
      ),
    );
    return ok(await items.insert(IssueProjection.apply(row, series)));
  }

  test(
    'same ISSN under another UID re-anchors and projects a new issue',
    () async {
      await seedSeries(
        const Periodical(
          title: 'Local Frontline',
          periodicalUid: 'local-series',
          issn: '1234-5679',
          publisher: 'Local publisher',
          language: 'English',
        ),
      );

      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [
              _series(
                'foreign-series',
                'Incoming Frontline',
                issn: '12345679',
                publisher: 'Incoming publisher',
              ),
            ],
            books: [_issue('new-issue', 'foreign-series', issueNumber: 5)],
          ),
        ),
      );

      expect(summary.periodicalsSkipped, 1);
      expect(summary.booksAdded, 1);
      expect(await storedSeries(), hasLength(1));
      final issue = (await storedItems()).single;
      expect(issue.issue?.periodicalUid, 'local-series');
      expect(issue.title, 'Local Frontline — No 5');
      expect(issue.publisher, 'Local publisher');
      expect(issue.language, 'English');
    },
  );

  test(
    'same ISSN import cannot move a same-UID issue to a missing series',
    () async {
      final local = await seedSeries(
        const Periodical(
          title: 'Local Frontline',
          periodicalUid: 'local-series',
          issn: '1234-5679',
        ),
      );
      await seedIssue(local, 'existing-issue', issueNumber: 5);

      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [
              _series('foreign-series', 'Incoming', issn: '1234-5679'),
            ],
            books: [_issue('existing-issue', 'foreign-series', issueNumber: 5)],
          ),
        ),
      );

      expect(summary.booksUpdated, 1);
      final issue = (await storedItems()).single;
      expect(issue.issue?.periodicalUid, 'local-series');
      expect(issue.title, 'Local Frontline — No 5');
    },
  );

  test(
    'same-UID plain JSON re-import preserves the local series cover',
    () async {
      final directory = Directory.systemTemp.createTempSync('s4_series_cover');
      addTearDown(() => directory.deleteSync(recursive: true));
      const leaf = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg';
      const coverRef = 'covers/$leaf';
      final cover = File('${directory.path}/$leaf')
        ..writeAsBytesSync(const [1, 2, 3]);
      await seedSeries(
        const Periodical(
          title: 'Old name',
          periodicalUid: 'series-1',
          coverUrl: coverRef,
        ),
      );

      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [
              _series(
                'series-1',
                'New name',
                coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
              ),
            ],
          ),
        ),
      );

      expect(summary.periodicalsUpdated, 1);
      expect((await storedSeries()).single.coverUrl, coverRef);
      final janitor = CoverFileJanitor(
        books: items,
        wishlist: wishlist,
        periodicals: periodicals,
        settings: FakeSettings(),
        store: CoverStore(coversDir: directory.path),
        coordinator: CoverFileCoordinator(),
      );
      expect(await janitor.sweep(), 0);
      expect(cover.readAsBytesSync(), const [1, 2, 3]);
    },
  );

  test(
    'same-UID import preserves missing addedDate and addedBy metadata',
    () async {
      await seedSeries(
        const Periodical(
          title: 'Old name',
          periodicalUid: 'series-1',
          addedDate: 1234,
          addedBy: 'local-maintainer',
        ),
      );

      ok(
        await useCase().importText(
          _json(periodicals: [_series('series-1', 'New name')]),
        ),
      );

      final stored = (await storedSeries()).single;
      expect(stored.addedDate, 1234);
      expect(stored.addedBy, 'local-maintainer');
    },
  );

  for (final includeOneIssue in [true, false]) {
    test('same-UID rename reprojects every local issue '
        '(include one: $includeOneIssue)', () async {
      final local = await seedSeries(
        const Periodical(
          title: 'Old name',
          periodicalUid: 'series-1',
          publisher: 'Old publisher',
        ),
      );
      await seedIssue(local, 'issue-1', issueNumber: 1);
      await seedIssue(local, 'issue-2', issueNumber: 2);

      ok(
        await useCase().importText(
          _json(
            periodicals: [
              _series('series-1', 'New name', publisher: 'New publisher'),
            ],
            books: [
              if (includeOneIssue)
                _issue('issue-1', 'series-1', issueNumber: 1),
            ],
          ),
        ),
      );

      final stored = await storedItems();
      expect(stored, hasLength(2));
      for (final issue in stored) {
        final number = issue.issue!.issueNumber!;
        expect(issue.title, 'New name — No $number');
        expect(issue.publisher, 'New publisher');
      }
    });
  }

  test('a v3 book cannot overwrite a stored issue with the same UID', () async {
    final local = await seedSeries(
      const Periodical(title: 'Frontline', periodicalUid: 'series-1'),
    );
    await seedIssue(local, 'shared-uid', issueNumber: 7);

    final result = await useCase().importText(
      _json(
        schemaVersion: 3,
        books: [
          {'bookUid': 'shared-uid', 'title': 'Legacy book'},
        ],
      ),
    );

    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    final stored = (await storedItems()).single;
    expect(stored.kind, ItemKind.magazineIssue);
    expect(stored.issue?.periodicalUid, 'series-1');
    expect(stored.issue?.issueNumber, 7);
    expect(stored.title, 'Frontline — No 7');
  });

  for (final existingKind in ItemKind.values) {
    for (final incomingKind in ItemKind.values) {
      if (existingKind == incomingKind) continue;
      test(
        'same-UID ${existingKind.name} → ${incomingKind.name} is refused',
        () async {
          Periodical? localSeries;
          if (existingKind == ItemKind.magazineIssue ||
              incomingKind == ItemKind.magazineIssue) {
            localSeries = await seedSeries(
              const Periodical(title: 'Frontline', periodicalUid: 'series-1'),
            );
          }
          final CatalogueItem original;
          if (existingKind == ItemKind.magazineIssue) {
            original = await seedIssue(
              localSeries!,
              'shared-uid',
              issueNumber: 7,
            );
          } else {
            original = ok(
              await items.insert(
                CatalogueItem(
                  itemUid: 'shared-uid',
                  title: 'Original ${existingKind.name}',
                  coverUrl: 'covers/original.jpg',
                  notes: 'keep me',
                  details: existingKind == ItemKind.other
                      ? const OtherItemOf()
                      : null,
                ),
              ),
            );
          }
          final incoming = _plainItem('shared-uid', incomingKind);
          if (incomingKind == ItemKind.magazineIssue) {
            incoming['issue'] = {'periodicalUid': 'series-1', 'issueNumber': 8};
          }

          final result = await useCase().importText(
            _json(
              periodicals: [
                if (incomingKind == ItemKind.magazineIssue)
                  _series('series-1', 'Frontline'),
              ],
              books: [incoming],
            ),
          );

          expect(result.getLeft().toNullable(), isA<ValidationFailure>());
          final stored = (await storedItems()).single;
          expect(stored.id, original.id);
          expect(stored.kind, existingKind);
          expect(stored.title, original.title);
          expect(stored.coverUrl, original.coverUrl);
          expect(stored.notes, original.notes);
          expect(
            stored.details?.sameAs(original.details) ??
                (original.details == null && stored.details == null),
            isTrue,
          );
          expect(await storedSeries(), hasLength(localSeries == null ? 0 : 1));
        },
      );
    }
  }

  test(
    'different-UID D6 duplicates skip while valid and date-only rows import',
    () async {
      final local = await seedSeries(
        const Periodical(title: 'Frontline', periodicalUid: 'series-1'),
      );
      await seedIssue(local, 'owned-number', volume: 1, issueNumber: 2);
      await seedIssue(
        local,
        'owned-bound',
        issueDate: january,
        boundUntil: february,
      );

      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [_series('series-1', 'Frontline')],
            books: [
              _issue('duplicate-number', 'series-1', volume: 1, issueNumber: 2),
              _issue(
                'duplicate-bound',
                'series-1',
                issueDate: january,
                boundUntil: february,
              ),
              _issue('date-only-1', 'series-1', issueDate: march),
              _issue('date-only-2', 'series-1', issueDate: march),
              _issue('new-number', 'series-1', volume: 1, issueNumber: 3),
            ],
          ),
        ),
      );

      expect(summary.booksSkipped, 2);
      expect(summary.booksAdded, 3);
      final stored = await storedItems();
      expect(stored, hasLength(5));
      expect(stored.where((row) => row.itemUid == 'duplicate-number'), isEmpty);
      expect(stored.where((row) => row.itemUid == 'duplicate-bound'), isEmpty);
      expect(
        stored.where((row) => row.itemUid?.startsWith('date-only-') ?? false),
        hasLength(2),
      );
    },
  );

  test(
    'canonical duplicate series UIDs use first-wins and count the later row',
    () async {
      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [
              _series('series-1', 'First valid'),
              _series('series-1', 'Later conflicting'),
            ],
            books: [_issue('issue-1', 'series-1', issueNumber: 1)],
          ),
        ),
      );

      expect(summary.periodicalsAdded, 1);
      expect(summary.periodicalsSkipped, 1);
      expect(summary.periodicalsUpdated, 0);
      expect((await storedSeries()).single.title, 'First valid');
      expect((await storedItems()).single.title, 'First valid — No 1');
    },
  );

  test(
    'an in-file duplicate ISSN resolves both incoming UIDs to the first series',
    () async {
      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [
              _series('series-1', 'First valid', issn: '1234-5679'),
              _series('series-2', 'Later conflicting', issn: '1234-5679'),
            ],
            books: [
              _issue('issue-1', 'series-1', issueNumber: 1),
              _issue('issue-2', 'series-2', issueNumber: 2),
            ],
          ),
        ),
      );

      expect(summary.periodicalsAdded, 1);
      expect(summary.periodicalsSkipped, 1);
      expect(await storedSeries(), hasLength(1));
      final stored = await storedItems();
      expect(stored, hasLength(2));
      for (final issue in stored) {
        expect(issue.issue?.periodicalUid, 'series-1');
        expect(issue.title, startsWith('First valid — '));
      }
    },
  );

  test(
    'trim-created series UID collision refuses and rolls back every store',
    () async {
      await seedSeries(
        const Periodical(
          title: 'Original series',
          periodicalUid: 'series-1',
          addedDate: 100,
        ),
      );
      ok(
        await items.insert(
          const CatalogueItem(title: 'Original item', itemUid: 'original-item'),
        ),
      );
      ok(
        await wishlist.insert(
          const WishlistBook(title: 'Original wish', isbn: 'old-wish'),
        ),
      );

      final result = await useCase().importText(
        _json(
          periodicals: [
            _series(' series-1 ', 'First spelling'),
            _series('series-1', 'Second spelling'),
          ],
          books: [
            {'bookUid': 'new-item', 'title': 'Must roll back'},
          ],
          wishlist: [
            {'title': 'Must also roll back', 'isbn': 'new-wish'},
          ],
        ),
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect((await storedSeries()).single.title, 'Original series');
      expect((await storedItems()).single.title, 'Original item');
      expect(ok(await wishlist.getAll()).single.title, 'Original wish');
    },
  );

  test(
    'in-file duplicate D6 issues skip without aborting valid rows',
    () async {
      final summary = ok(
        await useCase().importText(
          _json(
            periodicals: [_series('series-1', 'Frontline')],
            books: [
              _issue('issue-1', 'series-1', volume: 2, issueNumber: 10),
              _issue('issue-2', 'series-1', volume: 2, issueNumber: 10),
              _issue('issue-3', 'series-1', volume: 2, issueNumber: 11),
            ],
          ),
        ),
      );

      expect(summary.booksAdded, 2);
      expect(summary.booksSkipped, 1);
      expect(await storedItems(), hasLength(2));
    },
  );

  test('a repeated item UID releases its previous in-file D6 claim', () async {
    final summary = ok(
      await useCase().importText(
        _json(
          periodicals: [_series('series-1', 'Frontline')],
          books: [
            _issue('same-item', 'series-1', issueNumber: 1),
            _issue('same-item', 'series-1', issueNumber: 2),
            _issue('new-item', 'series-1', issueNumber: 1),
          ],
        ),
      ),
    );

    expect(summary.booksAdded, 2);
    expect(summary.booksUpdated, 1);
    expect(summary.booksSkipped, 0);
    final stored = await storedItems();
    expect(stored, hasLength(2));
    expect(
      stored
          .singleWhere((row) => row.itemUid == 'same-item')
          .issue
          ?.issueNumber,
      2,
    );
    expect(
      stored.singleWhere((row) => row.itemUid == 'new-item').issue?.issueNumber,
      1,
    );
  });

  test(
    'a reprojection failure rolls back series, items and wishlist',
    () async {
      final local = await seedSeries(
        const Periodical(title: 'Old name', periodicalUid: 'series-1'),
      );
      await seedIssue(local, 'local-issue', issueNumber: 1);
      ok(
        await wishlist.insert(
          const WishlistBook(title: 'Old wish', isbn: 'old-wish'),
        ),
      );
      final failingItems = _FailReprojectionItems(db, 'local-issue');
      final witnessingWishlist = _WitnessWishlist(db);

      final result =
          await ImportLibraryUseCase(
            jsonParser: const PitakaJsonImporter(),
            bookRepo: failingItems,
            wishlistRepo: witnessingWishlist,
            periodicalRepo: periodicals,
          ).importText(
            _json(
              periodicals: [_series('series-1', 'New name')],
              books: [
                {'bookUid': 'new-book', 'title': 'New book'},
              ],
              wishlist: [
                {'title': 'New wish', 'isbn': 'new-wish'},
                {'title': 'Changed wish', 'isbn': 'old-wish'},
              ],
            ),
          );

      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      expect(witnessingWishlist.insertedIsbns, ['new-wish']);
      expect(witnessingWishlist.upsertedIsbns, ['old-wish']);
      expect((await storedSeries()).single.title, 'Old name');
      expect((await storedItems()).single.title, 'Old name — No 1');
      expect(ok(await wishlist.getAll()).single.title, 'Old wish');
    },
  );
}

class _FailReprojectionItems extends DriftCatalogueItemRepository {
  _FailReprojectionItems(super.db, this.failingUid);

  final String failingUid;

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    if (book.itemUid == failingUid) {
      return left<Failure, CatalogueItem>(
        const StorageFailure('synthetic reprojection failure'),
      );
    }
    return super.update(book);
  }
}

class _WitnessWishlist extends DriftWishlistRepository {
  _WitnessWishlist(super.db);

  final insertedIsbns = <String>[];
  final upsertedIsbns = <String>[];

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) {
    insertedIsbns.add(book.isbn ?? '');
    return super.insert(book);
  }

  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) {
    upsertedIsbns.add(book.isbn ?? '');
    return super.upsert(book);
  }
}
