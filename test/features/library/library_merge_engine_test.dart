import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
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

      test('N07/M09: a local photo vs a remote cover is NOT a conflict', () {
        // After M09 a device with remote covers ON downloads the https cover
        // and stores it as a local file; a device with it OFF keeps the URL.
        // Both show the same picture, and M09's precedence (a local photo is
        // never replaced by an incoming URL) makes "take theirs" a no-op for
        // this field — so surfacing it gave the user a conflict they could
        // not resolve into anything different. Either direction is identical.
        final photo = [
          book(id: 1, uid: 'u1', title: 'Godaan', coverUrl: 'covers/a.jpg'),
        ];
        final url = [
          book(
            id: 99,
            uid: 'u1',
            title: 'Godaan',
            coverUrl: 'https://covers.openlibrary.org/b/1-L.jpg',
          ),
        ];

        expect(planMerge(photo, url).isNoOp, isTrue);
        expect(planMerge(url, photo).isNoOp, isTrue);
      });

      test('a remote cover vs NO cover is still a real conflict', () {
        // One device has a cover the other has nothing for: taking theirs
        // DOES change the local row, so the maintainer must see it.
        final local = [book(id: 1, uid: 'u1', title: 'Godaan')];
        final incoming = [
          book(
            id: 99,
            uid: 'u1',
            title: 'Godaan',
            coverUrl: 'https://covers.openlibrary.org/b/1-L.jpg',
          ),
        ];

        expect(planMerge(local, incoming).conflicts, hasLength(1));
        expect(planMerge(incoming, local).conflicts, hasLength(1));
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

  // N07 part 2 (astra-review.md): the review UI needs to SHOW what differs
  // and WHY a row is a possible duplicate — the engine only said "differs"
  // (a boolean) and "similarity 1.0" (which is also a legitimate fuzzy score
  // for identical title+author tokens, so kind cannot be inferred from it).
  group('N07 — review detail', () {
    test('a key collision is tagged identityKey; a fuzzy hit similarTitle', () {
      final local = [
        book(id: 1, uid: 'uA', title: 'Sapiens', isbn: '9780001'),
        // No ISBN: the fuzzy candidate. Tokens {sapiens, brief, history}.
        book(id: 5, uid: 'uE', title: 'Sapiens Brief History'),
      ];
      final incoming = [
        book(id: 2, uid: 'uB', title: 'Sapiens', isbn: '9780001'),
        book(id: 3, uid: 'uC', title: 'Sapiens (copy)', isbn: '9780001'),
        // Tokens {sapiens, brief} → Jaccard 2/3 ≈ 0.67 ≥ threshold, < 1.0.
        book(id: 4, uid: 'uD', title: 'Sapiens Brief'),
      ];

      final plan = planMerge(local, incoming);

      final byTitle = {
        for (final d in plan.possibleDuplicates) d.incoming.title: d,
      };
      expect(byTitle, hasLength(2));
      expect(
        byTitle['Sapiens (copy)']!.reason,
        DuplicateReason.identityKey,
        reason: 'ISBN held by the claimed local row',
      );
      expect(byTitle['Sapiens Brief']!.reason, DuplicateReason.similarTitle);
      expect(byTitle['Sapiens Brief']!.similarity, lessThan(1.0));
    });

    test('an in-file collision is tagged identityKey with the unpersisted '
        'earlier row as local', () {
      final incoming = [
        // Both unpersisted (id defaults to emptyId), like the importer's rows.
        book(uid: 'uB', title: 'Godaan'),
        book(uid: 'uB', title: 'Godaan (duplicate row)'),
      ];

      final plan = planMerge(const [], incoming);

      final dup = plan.possibleDuplicates.single;
      expect(dup.reason, DuplicateReason.identityKey);
      expect(dup.local.id, Book.emptyId);
    });

    test('a fuzzy hit with identical tokens scores 1.0 but is still '
        'similarTitle', () {
      // The ONLY reason the enum exists: 1.0 alone cannot tell the two apart.
      final local = [book(id: 1, uid: 'uA', title: 'Dohe', author: 'Kabir')];
      final incoming = [book(uid: 'uZ', title: 'Dohe', author: 'Kabir')];

      final plan = planMerge(local, incoming);

      final dup = plan.possibleDuplicates.single;
      expect(dup.similarity, 1.0);
      expect(dup.reason, DuplicateReason.similarTitle);
    });

    test('mergeDifferences lists exactly the differing fields, both sides', () {
      final a = book(id: 1, uid: 'u1', title: 'Godaan', genre: 'Fiction');
      final b = book(
        id: 2,
        uid: 'u2',
        title: 'Godaan',
        genre: 'Classic',
        copyCount: 3,
      );

      final diffs = mergeDifferences(a, b);

      expect(diffs.map((d) => d.field), [
        MergeField.genre,
        MergeField.copyCount,
      ]);
      final genre = diffs.first;
      expect(genre.local, 'Fiction');
      expect(genre.incoming, 'Classic');
      final copies = diffs.last;
      expect(copies.local, '1');
      expect(copies.incoming, '3');
    });

    test('mergeDifferences renders an unset side as null, not "null"', () {
      final a = book(id: 1, title: 'Godaan');
      final b = book(id: 2, title: 'Godaan', author: 'Premchand');

      final diff = mergeDifferences(a, b).single;

      expect(diff.field, MergeField.author);
      expect(diff.local, isNull);
      expect(diff.incoming, 'Premchand');
    });

    test('mergeDifferences follows the cover rule (local file is never a '
        'difference)', () {
      final a = book(id: 1, title: 'T', coverUrl: 'covers/abc.jpg');
      final b = book(
        id: 2,
        title: 'T',
        coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
      );
      expect(mergeDifferences(a, b), isEmpty);

      final c = book(id: 3, title: 'T');
      final diff = mergeDifferences(c, b).single;
      expect(diff.field, MergeField.cover);
      expect(diff.local, isNull);
      expect(diff.incoming, 'https://covers.openlibrary.org/b/id/1-L.jpg');
    });

    test('mergeDifferences ignores per-device bookkeeping (id, uid, '
        'addedDate, addedBy)', () {
      const a = Book(
        id: 1,
        bookUid: 'u1',
        title: 'T',
        addedDate: 1,
        addedBy: 'me',
      );
      const b = Book(
        id: 2,
        bookUid: 'u2',
        title: 'T',
        addedDate: 2,
        addedBy: 'you',
      );
      expect(mergeDifferences(a, b), isEmpty);
    });

    test('mergeEquals is exactly "mergeDifferences is empty" over every '
        'compared field', () {
      // Both must read the SAME field list, or a future field added to one
      // and not the other would make the summary lie about a conflict.
      const base = Book(
        id: 1,
        title: 'T',
        titleTransliteration: 'tt',
        author: 'a',
        isbn: '111',
        publisher: 'p',
        publishedYear: 2000,
        genre: 'g',
        coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
        pageCount: 10,
        language: 'hi',
        notes: 'n',
        location: 'l',
        sourceType: BookSourceType.gift,
        sourceDetail: 'sd',
        ageGroup: AgeGroup.above6,
        addedDate: 1,
        copyCount: 2,
      );
      final variants = <Book>[
        base.copyWith(title: 'X'),
        base.copyWith(titleTransliteration: 'X'),
        base.copyWith(author: 'X'),
        base.copyWith(isbn: '222'),
        base.copyWith(publisher: 'X'),
        base.copyWith(publishedYear: 2001),
        base.copyWith(genre: 'X'),
        base.copyWith(coverUrl: 'https://covers.openlibrary.org/b/id/2-L.jpg'),
        base.copyWith(pageCount: 11),
        base.copyWith(language: 'en'),
        base.copyWith(notes: 'X'),
        base.copyWith(location: 'X'),
        base.copyWith(sourceType: BookSourceType.donated),
        base.copyWith(sourceDetail: 'X'),
        base.copyWith(ageGroup: AgeGroup.advanced),
        base.copyWith(copyCount: 3),
        base.copyWith(needsMetadata: true),
        base.copyWith(removed: true),
      ];
      expect(variants, hasLength(MergeField.values.length));
      expect(mergeEquals(base, base), isTrue);
      expect(mergeDifferences(base, base), isEmpty);
      for (final v in variants) {
        expect(mergeEquals(base, v), isFalse);
        expect(mergeDifferences(base, v), hasLength(1));
      }
    });
  });
}
