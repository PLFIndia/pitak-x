import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/add_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/application/update_catalogue_item_use_case.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

T ok<T>(Either<Failure, T> e) =>
    e.getOrElse((f) => fail('unexpected failure: $f'));

/// First page of the list for the given intent (these tests seed a few rows,
/// so one page IS the list). N10-d part 2: `page` is the only list read.
Future<List<CatalogueItem>> firstPage(
  DriftCatalogueItemRepository repo, {
  required LibrarySort sort,
  String text = '',
  String? language,
}) async => ok<BookPage>(
  await repo.page(
    LibraryQuery(text: text, sort: sort, language: language),
    limit: libraryPageSize,
  ),
).items;

Failure err<T>(Either<Failure, T> e) =>
    e.fold((f) => f, (_) => fail('expected a failure'));

void main() {
  late AppDatabase db;
  late DriftCatalogueItemRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftCatalogueItemRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('repository getById + update', () {
    test('getById returns the inserted book, null for missing', () async {
      final inserted = ok(await repo.insert(const CatalogueItem(title: 'A')));
      final found = ok(await repo.getById(inserted.id));
      expect(found?.title, 'A');
      expect(ok(await repo.getById(999999)), isNull);
    });

    test('update edits fields and preserves id + book_uid', () async {
      final inserted = ok(await repo.insert(const CatalogueItem(title: 'Old')));
      final uid = inserted.itemUid;
      expect(uid, isNotNull);

      final edited = inserted.copyWith(title: 'New', author: 'Author');
      final updated = ok(await repo.update(edited));
      expect(updated.id, inserted.id);
      expect(updated.itemUid, uid); // merge key preserved

      final reread = ok(await repo.getById(inserted.id))!;
      expect(reread.title, 'New');
      expect(reread.author, 'Author');
      expect(reread.itemUid, uid);
    });

    test('update recovers book_uid if the edit dropped it', () async {
      final inserted = ok(
        await repo.insert(const CatalogueItem(title: 'Keep uid')),
      );
      final uid = inserted.itemUid;
      // Simulate a form that rebuilt the CatalogueItem without carrying the
      // uid.
      final edited = CatalogueItem(id: inserted.id, title: 'Edited no uid');
      final updated = ok(await repo.update(edited));
      expect(updated.itemUid, uid);
    });

    test('update of a non-existent row is NotFoundFailure', () async {
      final r = await repo.update(
        const CatalogueItem(id: 4242, title: 'ghost'),
      );
      expect(err(r), isA<NotFoundFailure>());
    });

    test('updated book is findable by new title via FTS search', () async {
      final inserted = ok(
        await repo.insert(const CatalogueItem(title: 'Alpha')),
      );
      await repo.update(inserted.copyWith(title: 'Bravo'));
      final hits = await firstPage(
        repo,
        text: 'Bravo',
        sort: LibrarySort.recentlyAdded,
      );
      expect(hits.map((b) => b.title), contains('Bravo'));
      final old = await firstPage(
        repo,
        text: 'Alpha',
        sort: LibrarySort.recentlyAdded,
      );
      expect(old, isEmpty);
    });

    test(
      'query sorts by language (blanks last) and filters by language',
      () async {
        await repo.insert(
          const CatalogueItem(title: 'Eng1', language: 'English'),
        );
        await repo.insert(const CatalogueItem(title: 'NoLang'));
        await repo.insert(
          const CatalogueItem(title: 'Hin1', language: 'Hindi'),
        );

        final byLang = await firstPage(repo, sort: LibrarySort.languageAsc);
        // English < Hindi, blank language sorts last.
        expect(byLang.map((b) => b.title).toList(), ['Eng1', 'Hin1', 'NoLang']);

        // N10-d D1-a: the facet is the STORED spelling (what the chip shows),
        // matched exactly — SQLite's lower() is ASCII-only, so a case-folded
        // compare silently missed non-Latin languages.
        final filtered = await firstPage(
          repo,
          sort: LibrarySort.recentlyAdded,
          language: 'Hindi',
        );
        expect(filtered.map((b) => b.title), ['Hin1']);
        final otherCase = await firstPage(
          repo,
          sort: LibrarySort.recentlyAdded,
          language: 'hindi',
        );
        expect(otherCase, isEmpty);
      },
    );

    test('distinctLanguages returns non-blank, sorted, deduped', () async {
      await repo.insert(const CatalogueItem(title: 'a', language: 'Hindi'));
      await repo.insert(const CatalogueItem(title: 'b', language: 'English'));
      await repo.insert(const CatalogueItem(title: 'c', language: 'Hindi'));
      await repo.insert(const CatalogueItem(title: 'd'));
      final langs = ok(await repo.distinctLanguages());
      expect(langs, ['English', 'Hindi']);
    });

    group('distinctSourceDetails', () {
      test("lists one type's non-blank details, sorted, trimmed", () async {
        await repo.insert(
          const CatalogueItem(
            title: 'a',
            sourceType: ItemSourceType.donated,
            sourceDetail: 'Sita Devi',
          ),
        );
        await repo.insert(
          const CatalogueItem(
            title: 'b',
            sourceType: ItemSourceType.donated,
            sourceDetail: '  Ram Sharma ',
          ),
        );
        // Same name under another type must NOT leak into "donated".
        await repo.insert(
          const CatalogueItem(
            title: 'c',
            sourceType: ItemSourceType.purchased,
            sourceDetail: 'Ram Sharma',
          ),
        );
        // Blank / absent details are not facet values.
        await repo.insert(
          const CatalogueItem(
            title: 'd',
            sourceType: ItemSourceType.donated,
            sourceDetail: '   ',
          ),
        );
        await repo.insert(
          const CatalogueItem(title: 'e', sourceType: ItemSourceType.donated),
        );
        await repo.insert(const CatalogueItem(title: 'f'));

        expect(ok(await repo.distinctSourceDetails(ItemSourceType.donated)), [
          'Ram Sharma',
          'Sita Devi',
        ]);
        expect(ok(await repo.distinctSourceDetails(ItemSourceType.purchased)), [
          'Ram Sharma',
        ]);
        expect(
          ok(await repo.distinctSourceDetails(ItemSourceType.gift)),
          isEmpty,
        );
      });

      test('collapses case variants into one entry (Unicode-aware)', () async {
        for (final spelling in const [
          'ram sharma',
          'Ram Sharma',
          'RAM SHARMA',
        ]) {
          await repo.insert(
            CatalogueItem(
              title: spelling,
              sourceType: ItemSourceType.donated,
              sourceDetail: spelling,
            ),
          );
        }
        await repo.insert(
          const CatalogueItem(
            title: 'g1',
            sourceType: ItemSourceType.donated,
            sourceDetail: 'Ελένη',
          ),
        );
        await repo.insert(
          const CatalogueItem(
            title: 'g2',
            sourceType: ItemSourceType.donated,
            sourceDetail: 'ΕΛΈΝΗ',
          ),
        );
        final details = ok(
          await repo.distinctSourceDetails(ItemSourceType.donated),
        );
        // One entry per person; the non-Latin pair dedupes too (SQLite's
        // NOCASE alone would have kept both Greek spellings).
        expect(details, hasLength(2));
        expect(details.map((d) => d.toLowerCase()).toSet(), {
          'ram sharma',
          'ελένη',
        });
      });
    });

    // Session 33: one spelling per language, enforced at the repository so
    // every ingress (form, import, merge, restore) obeys it.
    group('language canonicalisation on write', () {
      test(
        'insert snaps a case/space variant to the stored spelling',
        () async {
          await repo.insert(
            const CatalogueItem(title: 'a', language: 'English'),
          );
          final b = ok(
            await repo.insert(
              const CatalogueItem(title: 'b', language: ' english '),
            ),
          );
          final c = ok(
            await repo.insert(
              const CatalogueItem(title: 'c', language: 'ENGLISH'),
            ),
          );
          expect(b.language, 'English');
          expect(c.language, 'English');
          expect(ok(await repo.getById(b.id))?.language, 'English');
          expect(ok(await repo.distinctLanguages()), ['English']);
          // The exact-match facet (D1-a) now finds all three.
          final filtered = await firstPage(
            repo,
            sort: LibrarySort.recentlyAdded,
            language: 'English',
          );
          expect(filtered.map((b) => b.title).toSet(), {'a', 'b', 'c'});
        },
      );

      test(
        'insert keeps the FIRST spelling even when it is lowercase',
        () async {
          await repo.insert(
            const CatalogueItem(title: 'a', language: 'isiZulu'),
          );
          final b = ok(
            await repo.insert(
              const CatalogueItem(title: 'b', language: 'IsiZulu'),
            ),
          );
          expect(b.language, 'isiZulu');
          expect(ok(await repo.distinctLanguages()), ['isiZulu']);
        },
      );

      test(
        'insert converts an ISO 639-1 code to the stored/table name',
        () async {
          final first = ok(
            await repo.insert(const CatalogueItem(title: 'a', language: 'hi')),
          );
          expect(first.language, 'Hindi'); // nothing stored yet → table name
          await repo.insert(
            const CatalogueItem(title: 'b', language: 'english'),
          );
          final viaCode = ok(
            await repo.insert(
              const CatalogueItem(title: 'c', language: 'en-GB'),
            ),
          );
          expect(viaCode.language, 'english'); // snaps to the stored spelling
          expect(ok(await repo.distinctLanguages()), ['english', 'Hindi']);
        },
      );

      test(
        'non-Latin spellings round-trip and dedupe by Unicode case',
        () async {
          await repo.insert(
            const CatalogueItem(title: 'a', language: 'Ελληνικά'),
          );
          final b = ok(
            await repo.insert(
              const CatalogueItem(title: 'b', language: 'ΕΛΛΗΝΙΚΆ'),
            ),
          );
          expect(b.language, 'Ελληνικά');
          expect(ok(await repo.distinctLanguages()), ['Ελληνικά']);
        },
      );

      test(
        'update snaps too, and a lone book keeps its own spelling',
        () async {
          final only = ok(
            await repo.insert(
              const CatalogueItem(title: 'a', language: 'English'),
            ),
          );
          final edited = ok(
            await repo.update(only.copyWith(language: 'english')),
          );
          // Its own row is part of the stored set, so `English` stays.
          expect(edited.language, 'English');
          expect(ok(await repo.getById(only.id))?.language, 'English');
        },
      );

      test(
        'insertAll dedupes within the batch AND against stored rows',
        () async {
          await repo.insert(
            const CatalogueItem(title: 'seed', language: 'Hindi'),
          );
          final n = ok(
            await repo.insertAll(const [
              CatalogueItem(title: 'a', language: 'english'),
              CatalogueItem(title: 'b', language: 'English'),
              CatalogueItem(title: 'c', language: 'en'),
              CatalogueItem(title: 'd', language: 'HINDI'),
              CatalogueItem(title: 'e', language: 'Tamil'),
            ]),
          );
          expect(n, 5);
          // First spelling in the batch wins for the new language.
          expect(ok(await repo.distinctLanguages()), [
            'english',
            'Hindi',
            'Tamil',
          ]);
        },
      );

      test('replaceAll resolves only within the incoming file', () async {
        await repo.insert(
          const CatalogueItem(title: 'old', language: 'English'),
        );
        final n = ok(
          await repo.replaceAll(const [
            CatalogueItem(title: 'a', language: 'english'),
            CatalogueItem(title: 'b', language: 'ENGLISH'),
            CatalogueItem(title: 'c', language: 'hi'),
          ]),
        );
        expect(n, 3);
        // The old row is gone, so the file's own first spelling wins.
        expect(ok(await repo.distinctLanguages()), ['english', 'Hindi']);
      });

      test('absent language stays absent; blank stays blank', () async {
        final none = ok(await repo.insert(const CatalogueItem(title: 'a')));
        expect(none.language, isNull);
        final blank = ok(
          await repo.insert(const CatalogueItem(title: 'b', language: '   ')),
        );
        expect(blank.language, '   ');
        expect(ok(await repo.distinctLanguages()), isEmpty);
      });
    });

    test('query ageGroupAsc orders by band rank, nulls last', () async {
      await repo.insert(
        const CatalogueItem(title: 'adv', ageGroup: AgeGroup.advanced),
      );
      await repo.insert(const CatalogueItem(title: 'none'));
      await repo.insert(
        const CatalogueItem(title: 'a3', ageGroup: AgeGroup.above3),
      );
      final byAge = await firstPage(repo, sort: LibrarySort.ageGroupAsc);
      expect(byAge.map((b) => b.title).toList(), ['a3', 'adv', 'none']);
    });

    test('markRemoved sets removed+removedAt; restoreRemoved clears', () async {
      final ins = ok(await repo.insert(const CatalogueItem(title: 'Soft')));
      ok(await repo.markRemoved(ins.id, 999));
      final removed = ok(await repo.getById(ins.id))!;
      expect(removed.removed, isTrue);
      expect(removed.removedAt, 999);

      ok(await repo.restoreRemoved(ins.id));
      final back = ok(await repo.getById(ins.id))!;
      expect(back.removed, isFalse);
      expect(back.removedAt, isNull);
    });
  });

  group('AddCatalogueItemUseCase', () {
    test('rejects a blank title with ValidationFailure', () async {
      final useCase = AddCatalogueItemUseCase(repo);
      final r = await useCase(const CatalogueItem(title: '   '));
      expect(err(r), isA<ValidationFailure>());
    });

    test('inserts a valid book and mints a uid', () async {
      final useCase = AddCatalogueItemUseCase(repo);
      final saved = ok(await useCase(const CatalogueItem(title: 'Valid')));
      expect(saved.id, isNot(CatalogueItem.emptyId));
      expect(saved.itemUid, isNotNull);
    });

    test('M15: rejects copyCount 0 with ValidationFailure', () async {
      final useCase = AddCatalogueItemUseCase(repo);
      final r = await useCase(
        const CatalogueItem(title: 'Valid', copyCount: 0),
      );
      expect(err(r), isA<ValidationFailure>());
    });

    test('M15: rejects an out-of-range addedDate', () async {
      final useCase = AddCatalogueItemUseCase(repo);
      final r = await useCase(
        const CatalogueItem(title: 'Valid', addedDate: 8640000000000001),
      );
      expect(err(r), isA<ValidationFailure>());
    });

    // S34: the duplicate-ISBN routing the Kotlin app deferred. The UNIQUE
    // index always refused the row; the use case now says WHY, naming the
    // existing book, instead of letting a raw storage error surface.
    test('S34: a duplicate ISBN is refused as DuplicateIsbnFailure', () async {
      final useCase = AddCatalogueItemUseCase(repo);
      ok(
        await repo.insert(
          const CatalogueItem(title: 'First', isbn: '9780140449136'),
        ),
      );
      final failure = err(
        await useCase(
          const CatalogueItem(title: 'Second', isbn: '9780140449136'),
        ),
      );
      expect(failure, isA<DuplicateIsbnFailure>());
      failure as DuplicateIsbnFailure;
      expect(failure.existingTitle, 'First');
      expect(failure.existingIsRemoved, isFalse);
    });

    test(
      'S34: a duplicate of a REMOVED book carries the removed flag',
      () async {
        final useCase = AddCatalogueItemUseCase(repo);
        final first = ok(
          await repo.insert(const CatalogueItem(title: 'Gone', isbn: '333')),
        );
        ok(await repo.markRemoved(first.id, 42));
        final failure = err(
          await useCase(const CatalogueItem(title: 'Again', isbn: '333')),
        );
        expect(failure, isA<DuplicateIsbnFailure>());
        expect((failure as DuplicateIsbnFailure).existingIsRemoved, isTrue);
      },
    );

    test(
      'S34: blank ISBNs never collide — two no-ISBN books both save',
      () async {
        final useCase = AddCatalogueItemUseCase(repo);
        ok(await useCase(const CatalogueItem(title: 'No ISBN A')));
        ok(await useCase(const CatalogueItem(title: 'No ISBN B')));
        final all = await firstPage(repo, sort: LibrarySort.recentlyAdded);
        expect(
          all.map((b) => b.title),
          containsAll(['No ISBN A', 'No ISBN B']),
        );
      },
    );

    test(
      'S34: a failed duplicate pre-check aborts the add (fail closed)',
      () async {
        // If the library cannot even be READ, the use case must propagate the
        // read failure and never blind-insert: the index would catch a true
        // duplicate, but the honest error is "the check failed".
        final fake = _FailingFindByIsbnRepo();
        final useCase = AddCatalogueItemUseCase(fake);
        final failure = err(
          await useCase(const CatalogueItem(title: 'X', isbn: '9780140449136')),
        );
        expect(failure, isA<StorageFailure>());
        expect(fake.insertCalls, 0, reason: 'insert must not be attempted');
      },
    );
  });

  group('UpdateCatalogueItemUseCase', () {
    test('rejects a blank title', () async {
      final useCase = UpdateCatalogueItemUseCase(repo);
      final inserted = ok(await repo.insert(const CatalogueItem(title: 'X')));
      final r = await useCase(inserted.copyWith(title: ''));
      expect(err(r), isA<ValidationFailure>());
    });

    test('rejects an unpersisted book (emptyId) as NotFound', () async {
      final useCase = UpdateCatalogueItemUseCase(repo);
      final r = await useCase(const CatalogueItem(title: 'never saved'));
      expect(err(r), isA<NotFoundFailure>());
    });

    test('updates a persisted book', () async {
      final useCase = UpdateCatalogueItemUseCase(repo);
      final inserted = ok(
        await repo.insert(const CatalogueItem(title: 'Before')),
      );
      final saved = ok(await useCase(inserted.copyWith(title: 'After')));
      expect(saved.title, 'After');
      expect(saved.id, inserted.id);
    });

    test(
      'M15: a non-allow-listed remote cover is dropped, not rejected',
      () async {
        // Normalise-don't-reject: a pre-M15 row could already carry such a URL;
        // rejecting would make the book uneditable forever (the form copies
        // base.coverUrl verbatim). The inert link is dropped instead.
        final useCase = UpdateCatalogueItemUseCase(repo);
        final inserted = ok(
          await repo.insert(const CatalogueItem(title: 'Before')),
        );
        final saved = ok(
          await useCase(
            inserted.copyWith(coverUrl: 'https://evil.example/c.jpg'),
          ),
        );
        expect(saved.coverUrl, isNull);
        expect(ok(await repo.getById(inserted.id))!.coverUrl, isNull);
      },
    );
  });
}

/// A repository whose `findByIsbn` ALWAYS fails, to pin the fail-closed
/// pre-check (S34): when the duplicate check cannot be read, the add must
/// abort with the read failure — never blind-insert. Every other member is
/// an inert stub; the use case under test only touches these two.
class _FailingFindByIsbnRepo implements CatalogueItemRepository {
  int insertCalls = 0;

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      left(const StorageFailure('synthetic read failure'));

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    insertCalls++;
    return right(book);
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);
  @override
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async => right(BookPage.empty);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async =>
      right(books.length);
}
