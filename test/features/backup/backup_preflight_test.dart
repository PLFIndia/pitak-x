import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_preflight.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// BR3: the pure rules the backup writer asks before it builds a ZIP. No
/// file is touched here; the writer's own tests cover the file work
/// (`backup_writer_limits_test.dart`).
void main() {
  group('selectBackupCovers (decision D10)', () {
    CoverSelection select(
      List<CoverFileSize> files, {
      List<CatalogueItem> books = const [],
      List<WishlistBook> wishlist = const [],
      List<Periodical> periodicals = const [],
    }) => selectBackupCovers(
      files: files,
      maxCoverBytes: 100,
      books: books,
      wishlist: wishlist,
      periodicals: periodicals,
    );

    test('a cover exactly at the cap is kept; one byte over is left out', () {
      final selection = select(
        const [(leaf: 'at.jpg', bytes: 100), (leaf: 'over.jpg', bytes: 101)],
        books: const [
          CatalogueItem(id: 1, title: 'At the cap', coverUrl: 'covers/at.jpg'),
          CatalogueItem(id: 2, title: 'Over it', coverUrl: 'covers/over.jpg'),
        ],
      );
      expect(selection.kept, const [(leaf: 'at.jpg', bytes: 100)]);
      expect(selection.leftOutTitles, ['Over it']);
    });

    test('nothing oversized: every file is kept, in order, nobody named', () {
      final selection = select(
        const [(leaf: 'a.jpg', bytes: 1), (leaf: 'b.jpg', bytes: 100)],
        books: const [
          CatalogueItem(id: 1, title: 'A', coverUrl: 'covers/a.jpg'),
        ],
      );
      expect(selection.kept, const [
        (leaf: 'a.jpg', bytes: 1),
        (leaf: 'b.jpg', bytes: 100),
      ]);
      expect(selection.leftOutTitles, isEmpty);
    });

    test('an oversized file no item refers to is left out without a note', () {
      final selection = select(
        const [(leaf: 'orphan.jpg', bytes: 5000)],
        books: const [
          CatalogueItem(id: 1, title: 'Other', coverUrl: 'covers/else.jpg'),
          CatalogueItem(id: 2, title: 'No cover'),
        ],
      );
      expect(selection.kept, isEmpty);
      expect(selection.leftOutTitles, isEmpty);
    });

    test('books, wishlist entries and magazine titles are named, in that '
        'order', () {
      final selection = select(
        const [
          (leaf: 'book.jpg', bytes: 101),
          (leaf: 'series.jpg', bytes: 102),
          (leaf: 'wish.jpg', bytes: 103),
        ],
        books: const [
          CatalogueItem(id: 1, title: 'A book', coverUrl: 'covers/book.jpg'),
        ],
        wishlist: const [
          WishlistBook(id: 1, title: 'A wish', coverUrl: 'covers/wish.jpg'),
        ],
        periodicals: const [
          Periodical(
            title: 'A magazine',
            periodicalUid: 'p1',
            coverUrl: 'covers/series.jpg',
          ),
        ],
      );
      expect(selection.kept, isEmpty);
      expect(selection.leftOutTitles, ['A book', 'A wish', 'A magazine']);
    });

    test('every item that shares the picture is named', () {
      final selection = select(
        const [(leaf: 'shared.jpg', bytes: 101)],
        books: const [
          CatalogueItem(id: 1, title: 'First', coverUrl: 'covers/shared.jpg'),
          CatalogueItem(id: 2, title: 'Second', coverUrl: 'covers/shared.jpg'),
        ],
      );
      expect(selection.leftOutTitles, ['First', 'Second']);
    });

    test('a legacy file:// reference names its file too', () {
      final selection = select(
        const [(leaf: 'old.jpg', bytes: 101)],
        books: const [
          CatalogueItem(
            id: 1,
            title: 'Legacy',
            coverUrl: 'file:///data/user/0/app/files/covers/old.jpg',
          ),
        ],
      );
      expect(selection.leftOutTitles, ['Legacy']);
    });

    test('a remote cover or an unsafe reference names no file', () {
      final selection = select(
        const [(leaf: 'big.jpg', bytes: 101)],
        books: const [
          CatalogueItem(
            id: 1,
            title: 'Remote',
            coverUrl: 'https://example.org/big.jpg',
          ),
          CatalogueItem(
            id: 2,
            title: 'Traversal',
            coverUrl: 'covers/../big.jpg',
          ),
        ],
      );
      expect(selection.leftOutTitles, isEmpty);
    });
  });

  group('PlannedBackupEntry.content', () {
    test('hands out the content when it has the measured size', () {
      final entry = PlannedBackupEntry(
        'books.db',
        3,
        () => Uint8List.fromList([7, 8, 9]),
      );
      expect(entry.content(), [7, 8, 9]);
    });

    test('nothing is read before content() is called', () {
      var reads = 0;
      final entry = PlannedBackupEntry('cover_a.jpg', 2, () {
        reads++;
        return Uint8List(2);
      });
      expect(reads, 0);
      entry.content();
      expect(reads, 1);
    });

    test('a file that grew or shrank after it was measured fails closed', () {
      for (final actual in [2, 4]) {
        final entry = PlannedBackupEntry(
          'borrowers.db',
          3,
          () => Uint8List(actual),
        );
        expect(
          entry.content,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('borrowers.db'),
            ),
          ),
          reason: '$actual bytes read, 3 measured',
        );
      }
    });
  });

  group('backupRefusalFor', () {
    // Small limits, each cap different, so the code and the numbers of a
    // refusal show which rule fired.
    const limits = BackupLimits(
      maxCovers: 3,
      maxContentBytes: 1000,
      maxCoverBytes: 100,
      maxDatabaseBytes: 400,
      maxTextEntryBytes: 50,
    );

    PlannedBackupEntry entry(String name, int bytes) =>
        PlannedBackupEntry(name, bytes, () => Uint8List(bytes));

    List<PlannedBackupEntry> covers(int count, {int bytes = 1}) => [
      for (var i = 0; i < count; i++) entry('cover_$i.jpg', bytes),
    ];

    test('an empty backup and a small one fit', () {
      expect(backupRefusalFor(const [], limits), isNull);
      expect(
        backupRefusalFor([
          entry('manifest.json', 10),
          entry('books.db', 100),
          entry('wishlist.db', 100),
          ...covers(2),
        ], limits),
        isNull,
      );
    });

    test('covers: exactly the maximum fits, one more is refused', () {
      expect(backupRefusalFor(covers(3), limits), isNull);
      expect(backupRefusalFor(covers(4), limits), (
        code: BackupOverflow.tooManyCovers,
        actual: 4,
        limit: 3,
      ));
    });

    test('only names with the cover prefix count as covers', () {
      // Three covers plus the ten other entries: 13 entries, still fine.
      expect(
        backupRefusalFor([
          ...covers(3),
          entry('manifest.json', 1),
          entry('books.db', 1),
          entry('wishlist.db', 1),
          entry('borrowers.db', 1),
          entry('backup_blob', 1),
          entry('identity.json', 1),
          entry('network.json', 1),
          entry('item_kinds.json', 1),
          entry('periodicals.json', 1),
          entry('publish_state.json', 1),
        ], limits),
        isNull,
      );
    });

    group('one entry: exactly at its cap fits, one byte over is refused', () {
      void expectCap(String name, int cap, BackupOverflow code) {
        expect(backupRefusalFor([entry(name, cap)], limits), isNull);
        expect(backupRefusalFor([entry(name, cap + 1)], limits), (
          code: code,
          actual: cap + 1,
          limit: cap,
        ));
      }

      test('books.db', () {
        expectCap('books.db', 400, BackupOverflow.catalogueTooLarge);
      });
      test('wishlist.db', () {
        expectCap('wishlist.db', 400, BackupOverflow.wishlistTooLarge);
      });
      test('borrowers.db', () {
        expectCap('borrowers.db', 400, BackupOverflow.vaultTooLarge);
      });
      test('manifest.json and backup_blob', () {
        expectCap('manifest.json', 50, BackupOverflow.entryTooLarge);
        expectCap('backup_blob', 50, BackupOverflow.entryTooLarge);
      });
      test('a cover (the writer leaves such a cover out before it asks)', () {
        expectCap('cover_a.jpg', 100, BackupOverflow.entryTooLarge);
      });
    });

    test('an optional entry above its decoder cap is refused too', () {
      // The use case leaves such an entry out before the writer sees it;
      // this is the writer's own safety net. The cap is the decoder's, so it
      // needs limits that can hold more than 4 KiB of content.
      const roomy = BackupLimits(
        maxCovers: 1,
        maxContentBytes: 100000,
        maxCoverBytes: 10,
        maxDatabaseBytes: 10,
        maxTextEntryBytes: 10,
      );
      const cap = BackupIdentity.maxBytes;
      expect(backupRefusalFor([entry('identity.json', cap)], roomy), isNull);
      expect(backupRefusalFor([entry('identity.json', cap + 1)], roomy), (
        code: BackupOverflow.entryTooLarge,
        actual: cap + 1,
        limit: cap,
      ));
    });

    test('content: exactly the maximum fits, one byte more is refused', () {
      // 400 + 400 + 100 + 100 = 1,000 bytes, every entry within its own cap.
      final atLimit = [
        entry('books.db', 400),
        entry('wishlist.db', 400),
        entry('cover_a.jpg', 100),
        entry('cover_b.jpg', 100),
      ];
      expect(backupRefusalFor(atLimit, limits), isNull);
      expect(
        backupRefusalFor([...atLimit, entry('manifest.json', 1)], limits),
        (code: BackupOverflow.contentTooLarge, actual: 1001, limit: 1000),
      );
    });

    test('the checks run in order: covers, then one entry, then the sum', () {
      // Too many covers AND an oversized database AND too much content.
      final everythingWrong = [
        ...covers(4, bytes: 100),
        entry('books.db', 401),
        entry('wishlist.db', 400),
      ];
      expect(
        backupRefusalFor(everythingWrong, limits)?.code,
        BackupOverflow.tooManyCovers,
      );
      // Without the extra cover the oversized entry is reported next.
      expect(
        backupRefusalFor(everythingWrong.sublist(1), limits)?.code,
        BackupOverflow.catalogueTooLarge,
      );
    });

    test('an entry name without a cap is a bug, not a backup', () {
      expect(
        () => backupRefusalFor([entry('notes.txt', 1)], limits),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('notes.txt'),
          ),
        ),
      );
    });

    test('more than ten entries besides covers is a bug, not a backup', () {
      // The reader's entry limit is "covers + 10". An eleventh other entry
      // would make a library with the maximum of covers unrestorable.
      final eleven = [
        for (var i = 0; i < BackupLimits.otherEntries + 1; i++)
          entry('manifest.json', 1),
      ];
      expect(() => backupRefusalFor(eleven, limits), throwsStateError);
      expect(backupRefusalFor(eleven.sublist(1), limits), isNull);
    });
  });
}
