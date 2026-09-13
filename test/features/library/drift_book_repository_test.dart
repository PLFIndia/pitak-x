import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/book_sorter.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

T ok<T>(Either<Failure, T> either) =>
    either.getOrElse((f) => fail('unexpected failure: $f'));

/// Reads the WHOLE list for [query] through the paged API, page by page,
/// with a deliberately small [pageSize] so every test crosses several page
/// seams. This is how the controller consumes the repository (N10-d part 2);
/// there is no whole-list read any more.
Future<List<Book>> _allPages(
  DriftBookRepository repo,
  LibraryQuery query, {
  int pageSize = 7,
}) async {
  final out = <Book>[];
  var page = ok<BookPage>(await repo.page(query, limit: pageSize));
  out.addAll(page.items);
  // Guard against a repository that never says "done".
  var hops = 0;
  while (page.hasMore) {
    if (++hops > 1000) fail('hasMore never became false');
    page = ok<BookPage>(
      await repo.page(query, limit: pageSize, offset: out.length),
    );
    out.addAll(page.items);
  }
  return out;
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

    final hits = ok<BookPage>(
      await repo.page(
        LibraryQuery(text: 'witt', sort: BookSort.recentlyAdded), // prefix
        limit: libraryPageSize,
      ),
    );
    expect(hits.items.length, 1);
    expect(hits.items.single.title, 'Wittgenstein');
    expect(hits.hasMore, isFalse);
  });

  test('search neutralises FTS operators in user input', () async {
    await repo.insert(const Book(title: 'C++ Programming', addedDate: 1));
    // A bare '+' / quote must not crash the query.
    final res = await repo.page(
      LibraryQuery(text: 'C++ "', sort: BookSort.recentlyAdded),
      limit: libraryPageSize,
    );
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

  // N10-d (astra-review.md N10): a paginated read can only be correct if
  // SQLite produces the FINAL order and filter (part 1, S29) AND the page
  // boundary sits on that same statement (part 2). These tests pin both for
  // both list reads (blank text → plain select, typed text → FTS) against the
  // domain's ordering contract (`BookSorter`, N05), reading the fixture back
  // through SMALL pages so every seam is crossed.
  group('N10-d — order, filter and page are final in SQL', () {
    late List<Book> persisted;

    Future<void> seed(DriftBookRepository into) async {
      persisted = [];
      for (final b in _fixture()) {
        persisted.add(ok<Book>(await into.insert(b)));
      }
    }

    test(
      'page(ageGroupAsc, limit 3): the first 3 rows SQLite returns ARE the '
      'first 3 of the band order (no Dart re-sort left to fix them)',
      () async {
        // Insert order = alphabetical-token order, so an ORDER BY on the raw
        // token would hand the first page to above-10/above-15/above-3.
        final ids = <AgeGroup, int>{};
        for (final band in [
          AgeGroup.above10,
          AgeGroup.above15,
          AgeGroup.above3,
          AgeGroup.above6,
          AgeGroup.advanced,
        ]) {
          ids[band] = ok<Book>(
            await repo.insert(
              Book(title: band.token, ageGroup: band, addedDate: 1),
            ),
          ).id;
        }
        ok(await repo.insert(const Book(title: 'none', addedDate: 1)));

        final page = ok<BookPage>(
          await repo.page(LibraryQuery(sort: BookSort.ageGroupAsc), limit: 3),
        );
        expect(page.items.map((b) => b.id).toList(), [
          ids[AgeGroup.above3],
          ids[AgeGroup.above6],
          ids[AgeGroup.above10],
        ]);
        expect(page.hasMore, isTrue);
      },
    );

    test(
      'listing: every sort × language filter, read page by page, matches '
      'BookSorter on a seeded fixture (D1-a: exact stored language)',
      () async {
        await seed(repo);
        for (final sort in BookSort.values) {
          for (final lang in [null, 'Hindi', 'Ελληνικά']) {
            final got = (await _allPages(
              repo,
              LibraryQuery(sort: sort, language: lang),
            )).map((b) => b.id).toList();
            final want = _expectedIds(persisted, sort, lang);
            expect(want, isNotEmpty, reason: 'fixture guard $sort/$lang');
            expect(got, want, reason: 'sort=$sort language=$lang');
          }
        }
      },
    );

    test('search: every sort × language filter, read page by page, matches '
        'BookSorter — the FTS path pages the FINAL list too', () async {
      await seed(repo);
      for (final sort in BookSort.values) {
        for (final lang in [null, 'Hindi', 'Ελληνικά']) {
          final got = (await _allPages(
            repo,
            LibraryQuery(text: 'probe', sort: sort, language: lang),
          )).map((b) => b.id).toList();
          final want = _expectedIds(persisted, sort, lang);
          expect(want, isNotEmpty, reason: 'fixture guard $sort/$lang');
          expect(got, want, reason: 'sort=$sort language=$lang');
        }
      }
    });

    test(
      'search still narrows by the FTS match before ordering/filtering',
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
        final hits = ok<BookPage>(
          await repo.page(
            LibraryQuery(
              text: 'witt',
              sort: BookSort.recentlyAdded,
              language: 'Hindi',
            ),
            limit: libraryPageSize,
          ),
        );
        expect(hits.items.map((b) => b.title).toList(), ['Wittgenstein']);
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
      final listed = ok<BookPage>(
        await repo.page(
          LibraryQuery(sort: BookSort.recentlyAdded, language: 'Ελληνικά'),
          limit: libraryPageSize,
        ),
      );
      expect(listed.items.map((b) => b.title).toList(), ['probe greek']);
      final searched = ok<BookPage>(
        await repo.page(
          LibraryQuery(
            text: 'probe',
            sort: BookSort.recentlyAdded,
            language: 'Ελληνικά',
          ),
          limit: libraryPageSize,
        ),
      );
      expect(searched.items.map((b) => b.title).toList(), ['probe greek']);
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
          final listed = await _allPages(repo, LibraryQuery(sort: sort));
          expect(listed.map((x) => x.id).toList(), [
            a.id,
            b.id,
          ], reason: '$sort');
          final searched = await _allPages(
            repo,
            LibraryQuery(text: 'probe', sort: sort),
          );
          expect(searched.map((x) => x.id).toList(), [a.id, b.id]);
        }
      },
    );

    // Part 2 proper: the page contract itself.
    test('hasMore is true exactly while rows remain — both reads', () async {
      await seed(repo); // 40 rows
      for (final query in [
        LibraryQuery(sort: BookSort.recentlyAdded),
        LibraryQuery(text: 'probe', sort: BookSort.recentlyAdded),
      ]) {
        final first = ok<BookPage>(await repo.page(query, limit: 30));
        expect(first.items, hasLength(30), reason: '$query');
        expect(first.hasMore, isTrue, reason: '$query');
        final last = ok<BookPage>(
          await repo.page(query, limit: 30, offset: 30),
        );
        expect(last.items, hasLength(10), reason: '$query');
        expect(last.hasMore, isFalse, reason: '$query');
        // A page that ends EXACTLY on the last row must not claim more.
        final exact = ok<BookPage>(
          await repo.page(query, limit: 10, offset: 30),
        );
        expect(exact.items, hasLength(10));
        expect(exact.hasMore, isFalse, reason: 'exact end $query');
        final beyond = ok<BookPage>(
          await repo.page(query, limit: 10, offset: 40),
        );
        expect(beyond.items, isEmpty);
        expect(beyond.hasMore, isFalse);
      }
    });

    test('a page never contains more than limit rows (the +1 probe row is '
        'dropped, not leaked)', () async {
      await seed(repo);
      final page = ok<BookPage>(
        await repo.page(LibraryQuery(sort: BookSort.languageAsc), limit: 5),
      );
      expect(page.items, hasLength(5));
    });

    test('limit and offset are clamped at the boundary: a hostile caller '
        'cannot turn a page into a whole-catalogue read or ask SQLite for a '
        'negative window', () async {
      await seed(repo);
      final query = LibraryQuery(sort: BookSort.recentlyAdded);
      // limit <= 0 → the smallest useful page (1), not an error and not all.
      final zero = ok<BookPage>(await repo.page(query, limit: 0));
      expect(zero.items, hasLength(1));
      expect(zero.hasMore, isTrue);
      final negative = ok<BookPage>(await repo.page(query, limit: -9));
      expect(negative.items, hasLength(1));
      // offset < 0 → 0.
      final head = ok<BookPage>(await repo.page(query, limit: 3));
      final negOffset = ok<BookPage>(
        await repo.page(query, limit: 3, offset: -100),
      );
      expect(
        negOffset.items.map((b) => b.id).toList(),
        head.items.map((b) => b.id).toList(),
      );
      // limit > maxLibraryPageSize → maxLibraryPageSize. Seed enough rows to
      // prove the cap bites (40 fixture rows + 500 more = 540 > 500).
      for (var i = 0; i < maxLibraryPageSize; i++) {
        ok(await repo.insert(Book(title: 'bulk $i', addedDate: 5000 + i)));
      }
      final capped = ok<BookPage>(
        await repo.page(query, limit: maxLibraryPageSize * 10),
      );
      expect(capped.items, hasLength(maxLibraryPageSize));
      expect(capped.hasMore, isTrue);
    });

    test('a blank text with surrounding whitespace lists (not searches); the '
        'FTS path is only taken for real text', () async {
      await repo.insert(const Book(title: 'Solo', addedDate: 1));
      final listed = ok<BookPage>(
        await repo.page(
          LibraryQuery(text: '   ', sort: BookSort.recentlyAdded),
          limit: libraryPageSize,
        ),
      );
      expect(listed.items.map((b) => b.title).toList(), ['Solo']);
    });

    // D1-a (OFFSET, user decision S30): documented seam behaviour, not a
    // hidden one. A row inserted between two page reads that sorts BEFORE the
    // seam shifts everything down by one, so the next page repeats the last
    // row of the previous page. In the app every write path invalidates or
    // refreshes the list controller, which reloads from the top, so the UI
    // never reads page N+1 across its own write — this test exists so the
    // limitation is visible the day that stops being true.
    test('OFFSET seam (documented D1-a): an insert that sorts before the seam '
        'makes the next page repeat one row', () async {
      for (var i = 0; i < 6; i++) {
        ok(await repo.insert(Book(title: 'row $i', addedDate: 10 + i)));
      }
      final query = LibraryQuery(sort: BookSort.recentlyAdded);
      final first = ok<BookPage>(await repo.page(query, limit: 3));
      // Newest first: a row newer than everything lands at position 0.
      ok(await repo.insert(const Book(title: 'newest', addedDate: 999)));
      final second = ok<BookPage>(await repo.page(query, limit: 3, offset: 3));
      expect(second.items.first.id, first.items.last.id, reason: 'seam repeat');
      // Reloading from the top (what the controller does after a write) is
      // consistent again.
      final reloaded = await _allPages(repo, query, pageSize: 3);
      expect(reloaded.map((b) => b.id).toSet(), hasLength(7));
    });
  });
}
