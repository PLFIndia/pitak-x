import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';

T ok<T>(Either<Failure, T> either) =>
    either.getOrElse((f) => fail('unexpected failure: $f'));

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

  test(
    'insert mints a uid and round-trips every field incl. age token',
    () async {
      const book = Book(
        title: 'भारत: गांधी के बाद',
        author: 'Ramachandra Guha',
        ageGroup: AgeGroup.advanced,
        sourceType: BookSourceType.gift,
        addedDate: 100,
        copyCount: 3,
        removed: true,
        removedAt: 200,
      );

      final inserted = ok<Book>(await repo.insert(book));
      expect(inserted.bookUid, isNotNull);
      expect(inserted.id, greaterThan(0));

      final all = ok<List<Book>>(await repo.getAll());
      expect(all.length, 1);
      final got = all.single;
      expect(got.title, 'भारत: गांधी के बाद');
      expect(got.ageGroup, AgeGroup.advanced); // token persisted + parsed back
      expect(got.sourceType, BookSourceType.gift);
      expect(got.copyCount, 3);
      expect(got.removed, isTrue);
      expect(got.removedAt, 200);
      expect(got.bookUid, inserted.bookUid);
    },
  );

  test('search hits the FTS5 index and returns full domain books', () async {
    await repo.insert(
      const Book(title: 'Wittgenstein', author: 'Ray Monk', addedDate: 1),
    );
    await repo.insert(const Book(title: 'Gandhi', addedDate: 2));

    final hits = ok<List<Book>>(await repo.search('witt')); // prefix
    expect(hits.length, 1);
    expect(hits.single.title, 'Wittgenstein');
  });

  test('search neutralises FTS operators in user input', () async {
    await repo.insert(const Book(title: 'C++ Programming', addedDate: 1));
    // A bare '+' / quote must not crash the query.
    final res = await repo.search('C++ "');
    expect(res.isRight(), isTrue);
  });

  test('insertAll preserves existing uids and assigns missing ones', () async {
    final res = await repo.insertAll(const [
      Book(title: 'A', bookUid: 'keep-me', addedDate: 1),
      Book(title: 'B', addedDate: 2),
    ]);
    expect(ok<int>(res), 2);
    final all = ok<List<Book>>(await repo.getAll());
    final a = all.firstWhere((b) => b.title == 'A');
    final b = all.firstWhere((b) => b.title == 'B');
    expect(a.bookUid, 'keep-me');
    expect(b.bookUid, isNotNull);
  });

  test('findByIsbn returns the match, null for unknown/blank', () async {
    await repo.insert(const Book(title: 'X', isbn: '12345', addedDate: 1));
    expect(ok<Book?>(await repo.findByIsbn('12345'))!.title, 'X');
    expect(ok<Book?>(await repo.findByIsbn('nope')), isNull);
    expect(ok<Book?>(await repo.findByIsbn('')), isNull);
  });

  test(
    'delete hard-removes the row; deleting a missing id is a no-op',
    () async {
      final inserted = ok<Book>(
        await repo.insert(const Book(title: 'Doomed', addedDate: 1)),
      );
      ok<Unit>(await repo.delete(inserted.id));
      expect(ok<List<Book>>(await repo.getAll()), isEmpty);
      // Idempotent: deleting again does not throw / errors out.
      ok<Unit>(await repo.delete(inserted.id));
    },
  );

  // REVIEW_FINDINGS_2 S5: the merge apply paths must be atomic — reported
  // results must match committed state even when a row violates UNIQUE.
  group('atomicity', () {
    test(
      'insertAll rolls back entirely when one row violates UNIQUE isbn',
      () async {
        final res = await repo.insertAll(const [
          Book(title: 'A', isbn: '111', addedDate: 1),
          Book(title: 'B', isbn: '111', addedDate: 2),
        ]);
        expect(res.isLeft(), isTrue);
        // Nothing committed — not even the first, valid row.
        expect(ok<List<Book>>(await repo.getAll()), isEmpty);
      },
    );

    test('replaceAll swaps the catalogue and keeps incoming uids', () async {
      await repo.insert(
        const Book(title: 'Old', bookUid: 'old-uid', addedDate: 1),
      );
      final res = await repo.replaceAll(const [
        Book(title: 'New1', bookUid: 'keep-uid', addedDate: 2),
        Book(title: 'New2', addedDate: 3),
      ]);
      expect(ok<int>(res), 2);
      final all = ok<List<Book>>(await repo.getAll());
      expect(all.map((b) => b.title), unorderedEquals(['New1', 'New2']));
      expect(all.firstWhere((b) => b.title == 'New1').bookUid, 'keep-uid');
      expect(all.firstWhere((b) => b.title == 'New2').bookUid, isNotNull);
    });

    test('replaceAll rolls back the deletes when an insert fails', () async {
      await repo.insert(
        const Book(title: 'Old', bookUid: 'old-uid', isbn: '999', addedDate: 1),
      );
      // Crafted file: two rows sharing one ISBN — the second insert violates
      // the UNIQUE index AFTER the catalogue was deleted.
      final res = await repo.replaceAll(const [
        Book(title: 'New1', isbn: '111', addedDate: 2),
        Book(title: 'New2', isbn: '111', addedDate: 3),
      ]);
      expect(res.isLeft(), isTrue);
      // The pre-overwrite catalogue is fully intact.
      final all = ok<List<Book>>(await repo.getAll());
      expect(all, hasLength(1));
      expect(all.single.title, 'Old');
      expect(all.single.bookUid, 'old-uid');
    });

    test(
      'blank ISBNs are stored as NULL (unique-among-non-null holds)',
      () async {
        // Only a crafted import produces isbn '' (the UI trims to null); two
        // such rows must not collide on the UNIQUE index.
        final res = await repo.insertAll(const [
          Book(title: 'A', isbn: '', addedDate: 1),
          Book(title: 'B', isbn: '  ', addedDate: 2),
        ]);
        expect(ok<int>(res), 2);
        final all = ok<List<Book>>(await repo.getAll());
        expect(all.map((b) => b.isbn), everyElement(isNull));
      },
    );

    // runInTransaction (review 2026-09-03): the import use case wraps its
    // per-row writes in this, so a failure on row N must roll back rows
    // 1..N-1 — no more "3 of 5 books landed and a generic error".
    test(
      'runInTransaction rolls back every write when the body fails',
      () async {
        ok(await repo.insert(const Book(title: 'Keep', bookUid: 'keep')));
        final result = await repo.runInTransaction<int>(() async {
          ok(await repo.insert(const Book(title: 'One', bookUid: 'u1')));
          ok(await repo.insert(const Book(title: 'Two', bookUid: 'u2')));
          // A UNIQUE collision on book_uid → Left → whole transaction undone.
          final dup = await repo.insert(
            const Book(title: 'Dup', bookUid: 'u1'),
          );
          if (dup.isLeft()) return dup.map((_) => 0);
          return right(3);
        });
        expect(result.isLeft(), isTrue);
        final all = ok<List<Book>>(await repo.getAll());
        expect(all.map((b) => b.title), [
          'Keep',
        ], reason: 'One/Two rolled back');
      },
    );

    test('runInTransaction commits when the body succeeds', () async {
      final result = await repo.runInTransaction<int>(() async {
        ok(await repo.insert(const Book(title: 'One')));
        ok(await repo.insert(const Book(title: 'Two')));
        return right(2);
      });
      expect(ok<int>(result), 2);
      expect(ok<List<Book>>(await repo.getAll()), hasLength(2));
    });

    test('findByUid finds by stable identity; blank → null', () async {
      ok(await repo.insert(const Book(title: 'A', bookUid: 'abc')));
      expect(ok<Book?>(await repo.findByUid('abc'))?.title, 'A');
      expect(ok<Book?>(await repo.findByUid('zzz')), isNull);
      expect(ok<Book?>(await repo.findByUid('  ')), isNull);
    });
  });
}
