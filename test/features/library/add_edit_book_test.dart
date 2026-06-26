import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/add_book_use_case.dart';
import 'package:pitaka/features/library/application/update_book_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

T ok<T>(Either<Failure, T> e) =>
    e.getOrElse((f) => fail('unexpected failure: $f'));

Failure err<T>(Either<Failure, T> e) =>
    e.fold((f) => f, (_) => fail('expected a failure'));

void main() {
  late AppDatabase db;
  late DriftBookRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftBookRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('repository getById + update', () {
    test('getById returns the inserted book, null for missing', () async {
      final inserted = ok(await repo.insert(const Book(title: 'A')));
      final found = ok(await repo.getById(inserted.id));
      expect(found?.title, 'A');
      expect(ok(await repo.getById(999999)), isNull);
    });

    test('update edits fields and preserves id + book_uid', () async {
      final inserted = ok(await repo.insert(const Book(title: 'Old')));
      final uid = inserted.bookUid;
      expect(uid, isNotNull);

      final edited = inserted.copyWith(title: 'New', author: 'Author');
      final updated = ok(await repo.update(edited));
      expect(updated.id, inserted.id);
      expect(updated.bookUid, uid); // merge key preserved

      final reread = ok(await repo.getById(inserted.id))!;
      expect(reread.title, 'New');
      expect(reread.author, 'Author');
      expect(reread.bookUid, uid);
    });

    test('update recovers book_uid if the edit dropped it', () async {
      final inserted = ok(await repo.insert(const Book(title: 'Keep uid')));
      final uid = inserted.bookUid;
      // Simulate a form that rebuilt the Book without carrying the uid.
      final edited = Book(id: inserted.id, title: 'Edited no uid');
      final updated = ok(await repo.update(edited));
      expect(updated.bookUid, uid);
    });

    test('update of a non-existent row is NotFoundFailure', () async {
      final r = await repo.update(const Book(id: 4242, title: 'ghost'));
      expect(err(r), isA<NotFoundFailure>());
    });

    test('updated book is findable by new title via FTS search', () async {
      final inserted = ok(await repo.insert(const Book(title: 'Alpha')));
      await repo.update(inserted.copyWith(title: 'Bravo'));
      final hits = ok(await repo.search('Bravo'));
      expect(hits.map((b) => b.title), contains('Bravo'));
      final old = ok(await repo.search('Alpha'));
      expect(old, isEmpty);
    });

    test(
      'query sorts by language (blanks last) and filters by language',
      () async {
        await repo.insert(const Book(title: 'Eng1', language: 'English'));
        await repo.insert(const Book(title: 'NoLang'));
        await repo.insert(const Book(title: 'Hin1', language: 'Hindi'));

        final byLang = ok(await repo.query(sort: BookSort.languageAsc));
        // English < Hindi, blank language sorts last.
        expect(byLang.map((b) => b.title).toList(), ['Eng1', 'Hin1', 'NoLang']);

        final filtered = ok(
          await repo.query(sort: BookSort.recentlyAdded, language: 'hindi'),
        );
        expect(filtered.map((b) => b.title), ['Hin1']);
      },
    );

    test('distinctLanguages returns non-blank, sorted, deduped', () async {
      await repo.insert(const Book(title: 'a', language: 'Hindi'));
      await repo.insert(const Book(title: 'b', language: 'English'));
      await repo.insert(const Book(title: 'c', language: 'Hindi'));
      await repo.insert(const Book(title: 'd'));
      final langs = ok(await repo.distinctLanguages());
      expect(langs, ['English', 'Hindi']);
    });

    test('query ageGroupAsc orders by band rank, nulls last', () async {
      await repo.insert(const Book(title: 'adv', ageGroup: AgeGroup.advanced));
      await repo.insert(const Book(title: 'none'));
      await repo.insert(const Book(title: 'a3', ageGroup: AgeGroup.above3));
      final byAge = ok(await repo.query(sort: BookSort.ageGroupAsc));
      expect(byAge.map((b) => b.title).toList(), ['a3', 'adv', 'none']);
    });

    test('markRemoved sets removed+removedAt; restoreRemoved clears', () async {
      final ins = ok(await repo.insert(const Book(title: 'Soft')));
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

  group('AddBookUseCase', () {
    test('rejects a blank title with ValidationFailure', () async {
      final useCase = AddBookUseCase(repo);
      final r = await useCase(const Book(title: '   '));
      expect(err(r), isA<ValidationFailure>());
    });

    test('inserts a valid book and mints a uid', () async {
      final useCase = AddBookUseCase(repo);
      final saved = ok(await useCase(const Book(title: 'Valid')));
      expect(saved.id, isNot(Book.emptyId));
      expect(saved.bookUid, isNotNull);
    });
  });

  group('UpdateBookUseCase', () {
    test('rejects a blank title', () async {
      final useCase = UpdateBookUseCase(repo);
      final inserted = ok(await repo.insert(const Book(title: 'X')));
      final r = await useCase(inserted.copyWith(title: ''));
      expect(err(r), isA<ValidationFailure>());
    });

    test('rejects an unpersisted book (emptyId) as NotFound', () async {
      final useCase = UpdateBookUseCase(repo);
      final r = await useCase(const Book(title: 'never saved'));
      expect(err(r), isA<NotFoundFailure>());
    });

    test('updates a persisted book', () async {
      final useCase = UpdateBookUseCase(repo);
      final inserted = ok(await repo.insert(const Book(title: 'Before')));
      final saved = ok(await useCase(inserted.copyWith(title: 'After')));
      expect(saved.title, 'After');
      expect(saved.id, inserted.id);
    });
  });
}
