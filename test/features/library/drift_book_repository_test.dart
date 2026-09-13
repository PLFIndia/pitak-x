import 'dart:math';

// Narrowed: drift's `isNull`/`isNotNull` expression helpers would shadow the
// flutter_test matchers of the same name.
import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/book_sorter.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

T ok<T>(Either<Failure, T> either) =>
    either.getOrElse((f) => fail('unexpected failure: $f'));

/// N10-d (D3-a): a test-only Drift interceptor that appends `LIMIT n` to
/// every SELECT touching `books`. It lets the test observe what SQLite
/// ITSELF returns as "the first n rows" of the repository's statement — the
/// exact question a paginated read (N10-d part 2) will ask. If the order is
/// finished in Dart after the query, the first n SQL rows are the wrong n.
final class _LimitBooksSelects extends QueryInterceptor {
  _LimitBooksSelects(this.limit);
  final int limit;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final isBooksSelect =
        statement.trimLeft().toUpperCase().startsWith('SELECT') &&
        statement.contains('books') &&
        !statement.contains('LIMIT');
    // Drift terminates its statements with ';' — the LIMIT must go BEFORE it.
    final body = statement.trimRight().endsWith(';')
        ? statement.trimRight().substring(0, statement.trimRight().length - 1)
        : statement;
    final sql = isBooksSelect ? '$body LIMIT $limit' : statement;
    return executor.runSelect(sql, args);
  }
}

/// Seeded fixture for the order/filter equivalence tests: every age band
/// plus none, four languages (blank, ASCII, and one non-ASCII) plus none,
/// deliberate `addedDate` ties, and titles that all share the FTS token
/// `probe` so a search returns the whole set. Seeded [Random] = repeatable
/// fixture, not security randomness.
List<Book> _fixture({int rows = 40, int seed = 20260913}) {
  final rnd = Random(seed);
  const bands = [...AgeGroup.values, null];
  const languages = ['Hindi', 'English', 'Ελληνικά', '', null];
  return List.generate(
    rows,
    (i) => Book(
      title: 'probe $i',
      ageGroup: bands[rnd.nextInt(bands.length)],
      language: languages[rnd.nextInt(languages.length)],
      // Few distinct dates → many ties, so the tie-break rules are exercised.
      addedDate: 1000 + rnd.nextInt(6),
    ),
  );
}

/// The Dart-side oracle: [BookSorter] over the persisted rows, narrowed to
/// [language] with the D1-a rule (exact match on the stored string).
List<int> _expectedIds(List<Book> all, BookSort sort, String? language) {
  final narrowed = language == null
      ? all
      : all.where((b) => b.language == language).toList();
  // Ties are broken by id ASC in SQL; the oracle must state the same rule so
  // the comparison is total (BookSorter alone is only stable on input order).
  final byId = List<Book>.of(narrowed)..sort((a, b) => a.id.compareTo(b.id));
  return BookSorter.sort(byId, sort).map((b) => b.id).toList();
}

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

    final hits = ok<List<Book>>(
      await repo.search('witt', sort: BookSort.recentlyAdded), // prefix
    );
    expect(hits.length, 1);
    expect(hits.single.title, 'Wittgenstein');
  });

  test('search neutralises FTS operators in user input', () async {
    await repo.insert(const Book(title: 'C++ Programming', addedDate: 1));
    // A bare '+' / quote must not crash the query.
    final res = await repo.search('C++ "', sort: BookSort.recentlyAdded);
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

  // N10-d part 1 (astra-review.md N10): a paginated read can only be correct
  // if SQLite produces the FINAL order and filter. These tests pin that for
  // both list reads (blank query → `query`, typed query → `search`) against
  // the domain's ordering contract (`BookSorter`, N05).
  group('N10-d — order and filter are final in SQL', () {
    late List<Book> persisted;

    Future<void> seed(DriftBookRepository into) async {
      persisted = [];
      for (final b in _fixture()) {
        persisted.add(ok<Book>(await into.insert(b)));
      }
    }

    test('query(ageGroupAsc): the first 3 rows SQLite returns ARE the first 3 '
        'of the band order (no Dart re-sort left to fix them)', () async {
      // Interceptor applied to a fresh DB — the shared `db` stays clean.
      final limited = AppDatabase(
        NativeDatabase.memory().interceptWith(_LimitBooksSelects(3)),
      );
      addTearDown(limited.close);
      final limitedRepo = DriftBookRepository(limited);
      // Insert order = alphabetical-token order, so an ORDER BY on the raw
      // token hands SQLite's first 3 rows to above-10/above-15/above-3.
      final ids = <AgeGroup, int>{};
      for (final band in [
        AgeGroup.above10,
        AgeGroup.above15,
        AgeGroup.above3,
        AgeGroup.above6,
        AgeGroup.advanced,
      ]) {
        ids[band] = ok<Book>(
          await limitedRepo.insert(
            Book(title: band.token, ageGroup: band, addedDate: 1),
          ),
        ).id;
      }
      ok(await limitedRepo.insert(const Book(title: 'none', addedDate: 1)));

      final page = ok<List<Book>>(
        await limitedRepo.query(sort: BookSort.ageGroupAsc),
      );
      expect(page, hasLength(3), reason: 'LIMIT 3 reached SQLite');
      expect(page.map((b) => b.id).toList(), [
        ids[AgeGroup.above3],
        ids[AgeGroup.above6],
        ids[AgeGroup.above10],
      ]);
    });

    test('query(): every sort × language filter matches BookSorter on a seeded '
        'fixture (D1-a: exact match on the stored language)', () async {
      await seed(repo);
      for (final sort in BookSort.values) {
        for (final lang in [null, 'Hindi', 'Ελληνικά']) {
          final got = ok<List<Book>>(
            await repo.query(sort: sort, language: lang),
          ).map((b) => b.id).toList();
          final want = _expectedIds(persisted, sort, lang);
          expect(want, isNotEmpty, reason: 'fixture guard $sort/$lang');
          expect(got, want, reason: 'sort=$sort language=$lang');
        }
      }
    });

    test(
      'search(): every sort × language filter matches BookSorter — the FTS '
      'path returns the FINAL list, nothing left for the controller',
      () async {
        await seed(repo);
        for (final sort in BookSort.values) {
          for (final lang in [null, 'Hindi', 'Ελληνικά']) {
            final got = ok<List<Book>>(
              await repo.search('probe', sort: sort, language: lang),
            ).map((b) => b.id).toList();
            final want = _expectedIds(persisted, sort, lang);
            expect(want, isNotEmpty, reason: 'fixture guard $sort/$lang');
            expect(got, want, reason: 'sort=$sort language=$lang');
          }
        }
      },
    );

    test(
      'search() still narrows by the FTS match before ordering/filtering',
      () async {
        await repo.insert(
          const Book(title: 'Wittgenstein', language: 'Hindi', addedDate: 1),
        );
        await repo.insert(
          const Book(title: 'Gandhi', language: 'Hindi', addedDate: 2),
        );
        await repo.insert(
          const Book(title: 'Wittgenstein 2', language: 'Tamil', addedDate: 3),
        );
        final hits = ok<List<Book>>(
          await repo.search(
            'witt',
            sort: BookSort.recentlyAdded,
            language: 'Hindi',
          ),
        );
        expect(hits.map((b) => b.title).toList(), ['Wittgenstein']);
      },
    );

    test('a non-ASCII language is found by both reads (SQLite lower() is '
        'ASCII-only; the filter must not depend on it)', () async {
      await repo.insert(
        const Book(title: 'probe greek', language: 'Ελληνικά', addedDate: 1),
      );
      await repo.insert(
        const Book(title: 'probe hindi', language: 'Hindi', addedDate: 2),
      );
      final listed = ok<List<Book>>(
        await repo.query(sort: BookSort.recentlyAdded, language: 'Ελληνικά'),
      );
      expect(listed.map((b) => b.title).toList(), ['probe greek']);
      final searched = ok<List<Book>>(
        await repo.search(
          'probe',
          sort: BookSort.recentlyAdded,
          language: 'Ελληνικά',
        ),
      );
      expect(searched.map((b) => b.title).toList(), ['probe greek']);
    });

    test(
      'exact ties (same sort key, same addedDate) come back id ASC',
      () async {
        final a = ok<Book>(
          await repo.insert(
            const Book(title: 'probe a', language: 'X', addedDate: 7),
          ),
        );
        final b = ok<Book>(
          await repo.insert(
            const Book(title: 'probe b', language: 'X', addedDate: 7),
          ),
        );
        for (final sort in BookSort.values) {
          final listed = ok<List<Book>>(await repo.query(sort: sort));
          expect(listed.map((x) => x.id).toList(), [
            a.id,
            b.id,
          ], reason: '$sort');
          final searched = ok<List<Book>>(
            await repo.search('probe', sort: sort),
          );
          expect(searched.map((x) => x.id).toList(), [a.id, b.id]);
        }
      },
    );
  });
}
