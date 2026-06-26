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
}
