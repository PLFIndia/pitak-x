import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// Faithful port of Kotlin `LibraryMergeEngineTest` (PLAN-merge.md S3).
void main() {
  Book book({
    int id = 0,
    String? uid,
    String title = 'Title',
    String? author,
    String? isbn,
    String? genre,
    String? coverUrl,
    bool removed = false,
    int copyCount = 1,
  }) => Book(
    id: id,
    bookUid: uid,
    title: title,
    author: author,
    isbn: isbn,
    genre: genre,
    coverUrl: coverUrl,
    addedDate: 1000,
    copyCount: copyCount,
    removed: removed,
  );

  group('uid identity', () {
    test('uid match identical is no-op', () {
      final local = [book(id: 1, uid: 'u1', title: 'Godaan', isbn: '111')];
      final incoming = [book(id: 99, uid: 'u1', title: 'Godaan', isbn: '111')];

      final plan = planMerge(local, incoming);

      expect(plan.identical, 1);
      expect(plan.toAdd, isEmpty);
      expect(plan.conflicts, isEmpty);
      expect(plan.isNoOp, isTrue);
    });

    test('uid match differing field is conflict', () {
      final local = [book(id: 1, uid: 'u1', title: 'Godaan', genre: 'Fiction')];
      final incoming = [
        book(id: 99, uid: 'u1', title: 'Godaan', genre: 'Classic'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts[0].matchedBy, MatchKind.uid);
      expect(plan.toAdd, isEmpty);
      expect(plan.identical, 0);
    });
  });

  group('ISBN identity', () {
    test('isbn match when no uid match, identical is no-op', () {
      // Same physical book scanned on two phones: different uids, same ISBN.
      final local = [
        book(id: 1, uid: 'uA', title: 'Sapiens', isbn: '978-0-00-1'),
      ];
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Sapiens', isbn: '9780001'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.identical, 1);
      expect(plan.conflicts, isEmpty);
      expect(plan.toAdd, isEmpty);
    });

    test('isbn match differing field is conflict matched by isbn', () {
      final local = [
        book(
          id: 1,
          uid: 'uA',
          title: 'Sapiens',
          isbn: '9780001',
          genre: 'History',
        ),
      ];
      final incoming = [
        book(
          id: 2,
          uid: 'uB',
          title: 'Sapiens',
          isbn: '9780001',
          genre: 'Anthropology',
        ),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts[0].matchedBy, MatchKind.isbn);
    });
  });

  group('add-new', () {
    test('incoming with isbn and no match is added', () {
      final local = [book(id: 1, uid: 'u1', title: 'Godaan', isbn: '111')];
      final incoming = [
        book(id: 5, uid: 'u2', title: 'Nineteen Eighty-Four', isbn: '222'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.toAdd.map((b) => b.title), ['Nineteen Eighty-Four']);
      expect(plan.conflicts, isEmpty);
    });

    test('incoming no-isbn no-similar-local is added', () {
      final local = [
        book(id: 1, title: 'Completely Different Book', author: 'X'),
      ];
      final incoming = [
        book(id: 5, uid: 'u2', title: 'Kabir Ke Dohe', author: 'Kabir'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.toAdd.map((b) => b.title), ['Kabir Ke Dohe']);
      expect(plan.possibleDuplicates, isEmpty);
    });
  });

  group('no-ISBN fuzzy', () {
    test('close title+author is possible duplicate, not added', () {
      // Two maintainers independently typed the same regional book, no ISBN,
      // different uids → must be surfaced, not silently doubled.
      final local = [
        book(id: 1, uid: 'uA', title: 'Kabir Ke Dohe', author: 'Kabir Das'),
      ];
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Kabir ke Dohe', author: 'Kabir Das'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.possibleDuplicates, hasLength(1));
      expect(
        plan.possibleDuplicates[0].similarity,
        greaterThanOrEqualTo(kDefaultFuzzyThreshold),
      );
      expect(plan.toAdd, isEmpty);
      expect(plan.conflicts, isEmpty);
    });

    test('weak similarity is added, not surfaced', () {
      final local = [book(id: 1, title: 'Kabir Ke Dohe', author: 'Kabir')];
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Tulsi Ramayan', author: 'Tulsidas'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.possibleDuplicates, isEmpty);
      expect(plan.toAdd.map((b) => b.title), ['Tulsi Ramayan']);
    });
  });

  group('soft-delete', () {
    test('removal-only difference is a conflict flagged removalOnly', () {
      final local = [book(id: 1, uid: 'u1', title: 'Godaan')];
      final incoming = [book(id: 2, uid: 'u1', title: 'Godaan', removed: true)];

      final plan = planMerge(local, incoming);

      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts[0].isRemovalOnly, isTrue);
      expect(plan.identical, 0);
      expect(plan.toAdd, isEmpty);
    });

    test('field+removal difference is not removalOnly', () {
      final local = [book(id: 1, uid: 'u1', title: 'Godaan', genre: 'A')];
      final incoming = [
        book(id: 2, uid: 'u1', title: 'Godaan', genre: 'B', removed: true),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts[0].isRemovalOnly, isFalse);
    });
  });

  group('robustness', () {
    test('two incoming books do not fan in onto one local row', () {
      final local = [book(id: 1, uid: 'uA', title: 'Sapiens', isbn: '9780001')];
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Sapiens', isbn: '9780001'),
        book(id: 3, uid: 'uC', title: 'Sapiens (copy)', isbn: '9780001'),
      ];

      final plan = planMerge(local, incoming);

      expect(plan.identical, 1);
      // The second incoming row's ISBN is held by the now-claimed local row,
      // so it can never be inserted (UNIQUE isbn). It is surfaced for review
      // instead of auto-added (REVIEW_FINDINGS_2 S5).
      expect(plan.toAdd, isEmpty);
      expect(plan.possibleDuplicates, hasLength(1));
      expect(plan.possibleDuplicates[0].incoming.title, 'Sapiens (copy)');
      expect(plan.possibleDuplicates[0].local.id, 1);
      expect(plan.possibleDuplicates[0].similarity, 1.0);
    });

    test('duplicate ISBN within one incoming file: first added, second '
        'surfaced', () {
      // REVIEW_FINDINGS_2 S5 Major: both rows used to land in toAdd; the
      // second insert then failed on the UNIQUE isbn index mid-apply.
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Sapiens', isbn: '9780001'),
        book(id: 3, uid: 'uC', title: 'Sapiens', isbn: '978 0001'),
      ];

      final plan = planMerge(const [], incoming);

      expect(plan.toAdd, hasLength(1));
      expect(plan.toAdd[0].bookUid, 'uB');
      expect(plan.possibleDuplicates, hasLength(1));
      expect(plan.possibleDuplicates[0].incoming.bookUid, 'uC');
      expect(plan.possibleDuplicates[0].local.bookUid, 'uB');
      expect(plan.possibleDuplicates[0].similarity, 1.0);
    });

    test('duplicate uid within one incoming file: first added, second '
        'surfaced', () {
      // Same UNIQUE-collision class via book_uid (no ISBNs involved).
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Godaan'),
        book(id: 3, uid: 'uB', title: 'Godaan (duplicate row)'),
      ];

      final plan = planMerge(const [], incoming);

      expect(plan.toAdd, hasLength(1));
      expect(plan.possibleDuplicates, hasLength(1));
      expect(
        plan.possibleDuplicates[0].incoming.title,
        'Godaan (duplicate row)',
      );
    });

    // Regression for REVIEW_FINDINGS_2 S5 Major: local cover refs are
    // per-device and never survive an export→import hop (the importer nulls
    // them), so they must not count as catalogue-state differences.
    group('cover normalisation', () {
      test('local cover vs null incoming cover is identical, not conflict', () {
        final local = [
          book(id: 1, uid: 'u1', title: 'Godaan', coverUrl: 'covers/abc.jpg'),
        ];
        final incoming = [book(id: 99, uid: 'u1', title: 'Godaan')];

        final plan = planMerge(local, incoming);

        expect(plan.isNoOp, isTrue);
        expect(plan.identical, 1);
      });

      test('two different local refs for the same book are identical', () {
        final local = [
          book(id: 1, uid: 'u1', title: 'Godaan', coverUrl: 'covers/a.jpg'),
        ];
        final incoming = [
          book(id: 99, uid: 'u1', title: 'Godaan', coverUrl: 'covers/b.jpg'),
        ];

        expect(planMerge(local, incoming).isNoOp, isTrue);
      });

      test('differing REMOTE covers remain a real conflict', () {
        final local = [
          book(
            id: 1,
            uid: 'u1',
            title: 'Godaan',
            coverUrl: 'https://covers.openlibrary.org/b/1-L.jpg',
          ),
        ];
        final incoming = [
          book(
            id: 99,
            uid: 'u1',
            title: 'Godaan',
            coverUrl: 'https://covers.openlibrary.org/b/2-L.jpg',
          ),
        ];

        final plan = planMerge(local, incoming);
        expect(plan.conflicts, hasLength(1));
      });

      test('local cover vs remote cover is a real conflict', () {
        // One device fetched a fetchable cover the other doesn't have — a
        // genuine catalogue-state difference the maintainer should see.
        final local = [
          book(id: 1, uid: 'u1', title: 'Godaan', coverUrl: 'covers/a.jpg'),
        ];
        final incoming = [
          book(
            id: 99,
            uid: 'u1',
            title: 'Godaan',
            coverUrl: 'https://covers.openlibrary.org/b/1-L.jpg',
          ),
        ];

        expect(planMerge(local, incoming).conflicts, hasLength(1));
      });
    });

    test('export → parse → planMerge round-trip is a no-op', () {
      // The exact two-maintainer flow: device A exports its library (local
      // covers and all), device B parses with keepLocalCovers=false and plans
      // the merge back against A's library — nothing may surface.
      final lib = [
        book(
          id: 1,
          uid: 'u1',
          title: 'Godaan',
          isbn: '111',
          coverUrl: 'covers/abc.jpg',
        ),
        book(id: 2, uid: 'u2', title: 'Kabir', author: 'Kabir'),
        book(
          id: 3,
          uid: 'u3',
          title: 'Sapiens',
          isbn: '978-0-00-1',
          coverUrl: 'https://covers.openlibrary.org/b/1-L.jpg',
        ),
      ];
      final json = const PitakaJsonExporter().export(
        books: lib,
        wishlist: const [],
        exportedAt: 1234,
      );
      final payload = const PitakaJsonImporter().parse(json); // merge mode
      expect(payload.parseErrors, isEmpty);
      // The local cover ref really was nulled by the parse (precondition).
      expect(
        payload.books.firstWhere((b) => b.bookUid == 'u1').coverUrl,
        isNull,
      );

      final plan = planMerge(lib, payload.books);

      expect(plan.isNoOp, isTrue);
      expect(plan.identical, 3);
    });

    test('merging the same export again is a no-op', () {
      final lib = [
        book(id: 1, uid: 'u1', title: 'Godaan', isbn: '111'),
        book(id: 2, uid: 'u2', title: 'Kabir', author: 'Kabir'),
      ];

      final plan = planMerge(lib, lib);

      expect(plan.isNoOp, isTrue);
      expect(plan.identical, 2);
    });

    test('empty inputs are no-op', () {
      expect(planMerge(const [], const []).isNoOp, isTrue);
    });

    test('all incoming added into empty local', () {
      final incoming = [
        book(id: 1, uid: 'u1', title: 'A', isbn: '111'),
        book(id: 2, uid: 'u2', title: 'B'),
      ];
      expect(planMerge(const [], incoming).toAdd, hasLength(2));
    });
  });

  group('helpers', () {
    test('normIsbn strips spaces/hyphens and uppercases', () {
      expect(normIsbn('978-0-00 1x'), '9780001X');
      expect(normIsbn(null), '');
    });

    test('jaccard basic', () {
      expect(jaccard({'a', 'b'}, {'a', 'b'}), 1.0);
      expect(jaccard({'a', 'b'}, {'c', 'd'}), 0.0);
      expect(jaccard({'a', 'b'}, {'a'}), closeTo(0.5, 1e-9));
    });

    test('tokenSet is script-agnostic and drops punctuation', () {
      final b = book(title: 'Kabir, Ke Dohe!', author: 'कबीर');
      final tokens = tokenSet(b);
      expect(tokens, contains('kabir'));
      expect(tokens, contains('dohe'));
      expect(tokens, contains('कबीर'));
      expect(tokens, isNot(contains(',')));
    });
  });
}
