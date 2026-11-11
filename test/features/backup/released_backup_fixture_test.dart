import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/replacement_harness.dart';
import '../publish/support/publish_state_fixtures.dart';

/// A backup made by the RELEASED app (the writer of tag 1.9.7) must keep
/// restoring, whatever later versions change in the writer or the reader.
///
/// Why this test exists (beginner note): the other backup tests build an
/// archive with today's writer and read it with today's reader, so the two
/// can change together and still agree. A user's old backup file cannot
/// change. `test/fixtures/backup/released_1_9_7.backup` is such an old file,
/// frozen; see the README next to it for how it was made. Never regenerate
/// it with a newer writer: that would defeat its purpose.
///
/// The expectations are written out in full on purpose. They say what is
/// inside the file, independent of any code that could change.
const String _fixtureDir = 'test/fixtures/backup';

T _unwrap<T>(Either<Failure, T> result) =>
    result.getOrElse((failure) => fail('Expected success, got: $failure'));

/// Every stored field of a catalogue item, as plain values. Comparing maps
/// gives a readable difference when one field is wrong.
Map<String, Object?> _itemFields(CatalogueItem item) => {
  'id': item.id,
  'itemUid': item.itemUid,
  'title': item.title,
  'titleTransliteration': item.titleTransliteration,
  'author': item.author,
  'isbn': item.isbn,
  'publisher': item.publisher,
  'publishedYear': item.publishedYear,
  'genre': item.genre,
  'coverUrl': item.coverUrl,
  'pageCount': item.pageCount,
  'language': item.language,
  'notes': item.notes,
  'location': item.location,
  'sourceType': item.sourceType,
  'sourceDetail': item.sourceDetail,
  'ageGroup': item.ageGroup,
  'addedDate': item.addedDate,
  'copyCount': item.copyCount,
  'needsMetadata': item.needsMetadata,
  'removed': item.removed,
  'removedAt': item.removedAt,
  'addedBy': item.addedBy,
  'kind': item.kind.name,
};

/// The expected fields of a row where only [set] differs from an empty row.
/// Keeps each expectation to the fields that carry a value, while still
/// checking that every OTHER field came back empty.
Map<String, Object?> _itemWith(Map<String, Object?> set) => {
  'id': 0,
  'itemUid': null,
  'title': '',
  'titleTransliteration': null,
  'author': null,
  'isbn': null,
  'publisher': null,
  'publishedYear': null,
  'genre': null,
  'coverUrl': null,
  'pageCount': null,
  'language': null,
  'notes': null,
  'location': null,
  'sourceType': null,
  'sourceDetail': null,
  'ageGroup': null,
  'addedDate': 0,
  'copyCount': 1,
  'needsMetadata': false,
  'removed': false,
  'removedAt': null,
  'addedBy': null,
  'kind': 'book',
  ...set,
};

/// The same for a wishlist entry (its id is not part of the promise).
Map<String, Object?> _wishFields(WishlistBook book) => {
  'title': book.title,
  'titleTransliteration': book.titleTransliteration,
  'author': book.author,
  'isbn': book.isbn,
  'publisher': book.publisher,
  'publishedYear': book.publishedYear,
  'coverUrl': book.coverUrl,
  'priceEstimate': book.priceEstimate,
  'priority': book.priority,
  'notes': book.notes,
  'source': book.source,
  'addedDate': book.addedDate,
  'purchased': book.purchased,
  'purchasedDate': book.purchasedDate,
  'needsMetadata': book.needsMetadata,
};

/// The same for a magazine title (its id is not part of the promise).
Map<String, Object?> _periodicalFields(Periodical p) => {
  'periodicalUid': p.periodicalUid,
  'title': p.title,
  'titleTransliteration': p.titleTransliteration,
  'issn': p.issn,
  'publisher': p.publisher,
  'language': p.language,
  'coverUrl': p.coverUrl,
  'frequency': p.frequency?.name,
  'subscriptionStart': p.subscriptionStart,
  'subscriptionEnd': p.subscriptionEnd,
  'notes': p.notes,
  'location': p.location,
  'sourceType': p.sourceType,
  'sourceDetail': p.sourceDetail,
  'ageGroup': p.ageGroup,
  'addedDate': p.addedDate,
  'removed': p.removed,
  'removedAt': p.removedAt,
  'addedBy': p.addedBy,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late ReplacementHarness h;
  late Uint8List archive;

  setUp(() {
    h = ReplacementHarness(generations: true);
    archive = File('$_fixtureDir/released_1_9_7.backup').readAsBytesSync();
  });
  tearDown(() => h.close());

  test('the file holds exactly the entries the released writer made', () {
    final files = BoundedZipExtractor.extract(archive);

    expect(files.keys.toSet(), {
      'manifest.json',
      'books.db',
      'wishlist.db',
      'borrowers.db',
      'backup_blob',
      'cover_0b1f-uuid.jpg',
      'cover_series-local.jpg',
      'identity.json',
      'network.json',
      'item_kinds.json',
      'periodicals.json',
      'publish_state.json',
    });
  });

  test('the reader that works from a file takes the same twelve entries, '
      'byte for byte (BR5)', () {
    // The new reader is stricter than the one above in three rules (the
    // size an entry declares, the name in its header, no zip64). A file
    // the released app wrote must pass all of them, with the rules a
    // restore will use: every entry known, every entry taken.
    final expected = BoundedZipExtractor.extract(archive);
    const limits = BackupLimits.current;
    final file = BoundedZipFile.open(
      '$_fixtureDir/released_1_9_7.backup',
      limits: ZipLimits.forBackup(limits),
      policy: (name) => backupEntryRule(name, limits),
    );
    addTearDown(file.close);

    expect(file.entries, hasLength(12));
    expect({for (final e in file.entries) e.name}, expected.keys.toSet());
    for (final entry in file.entries) {
      expect(entry.verdict, ZipEntryVerdict.take, reason: entry.name);
      expect(
        file.read(entry, maxBytes: backupEntryCap(entry.name, limits)!),
        expected[entry.name],
        reason: entry.name,
      );
    }
  });

  test('inspection reads what the file declares, without restoring', () async {
    final restorer = await h.container.read(restoreBackupProvider.future);

    final inspection = _unwrap(await restorer.inspectArchive(archive));

    final manifest = inspection.manifest;
    expect(
      {
        'schemaVersion': manifest.schemaVersion,
        'hasBooks': manifest.hasBooks,
        'hasWishlist': manifest.hasWishlist,
        'hasBorrowers': manifest.hasBorrowers,
        'hasBackupBlob': manifest.hasBackupBlob,
        'hasCovers': manifest.hasCovers,
        'hasIdentity': manifest.hasIdentity,
        'hasNetwork': manifest.hasNetwork,
        'hasItemKinds': manifest.hasItemKinds,
        'hasPeriodicals': manifest.hasPeriodicals,
        'hasPublishState': manifest.hasPublishState,
      },
      {
        'schemaVersion': 1,
        'hasBooks': true,
        'hasWishlist': true,
        'hasBorrowers': true,
        'hasBackupBlob': true,
        'hasCovers': true,
        'hasIdentity': true,
        'hasNetwork': true,
        'hasItemKinds': true,
        'hasPeriodicals': true,
        'hasPublishState': true,
      },
    );
    expect(inspection.identity!.id, 'f1e2d3c4b5a69788f1e2d3c4b5a69788');
    expect(inspection.identity!.name, 'Fixture Library');
    expect(inspection.publishState!.coverSalt, archiveSalt);
  });

  test('restore brings back every row, cover and the vault pair', () async {
    // The vault itself is ciphertext that only the Rust core can open, and
    // unit tests run without it. The fake stands in for "the passphrase was
    // right" and hands back loans that point at two items of the archive.
    h.vault.borrowers = [const Borrower(id: 1, name: 'Asha')];
    h.vault.loans.addAll(const [
      Loan(id: 1, itemId: 1, borrowerId: 1, lentDate: 500, dueDate: 600),
      Loan(id: 2, itemId: 3, borrowerId: 1, lentDate: 700, returnedDate: 800),
    ]);
    await h.initialize();
    var vaultWasRead = false;
    h.vault.onRead = () async => vaultWasRead = true;

    final restorer = await h.container.read(restoreBackupProvider.future);
    final passphrase = ReplacementHarness.secret();
    final result = await restorer.restore(
      archiveBytes: archive,
      passphrase: passphrase,
    );
    passphrase.dispose();
    final summary = _unwrap(result);

    // --- what the restore reports ---
    expect(vaultWasRead, isTrue);
    expect(
      {
        'booksRestored': summary.booksRestored,
        'wishlistRestored': summary.wishlistRestored,
        'periodicalsRestored': summary.periodicalsRestored,
        'kindsApplied': summary.kindsApplied,
        'issuesLinked': summary.issuesLinked,
        'issuesDetached': summary.issuesDetached,
        'issueEntriesDropped': summary.issueEntriesDropped,
        'periodicalsDropped': summary.periodicalsDropped,
        'rowsSkippedUnknownKind': summary.rowsSkippedUnknownKind,
        'coversDropped': summary.coversDropped,
        'borrowersRestored': summary.borrowersRestored,
        'loansRestored': summary.loansRestored,
        'networkRowsDropped': summary.networkRowsDropped,
      },
      {
        'booksRestored': 5,
        'wishlistRestored': 2,
        'periodicalsRestored': 2,
        'kindsApplied': 3,
        'issuesLinked': 2,
        'issuesDetached': 0,
        'issueEntriesDropped': 0,
        'periodicalsDropped': 0,
        'rowsSkippedUnknownKind': 0,
        'coversDropped': 0,
        'borrowersRestored': 1,
        'loansRestored': 2,
        'networkRowsDropped': 0,
      },
    );
    expect(summary.danglingLoans, isEmpty);
    expect(summary.isIntact, isTrue);
    expect(summary.existingVaultKept, isFalse);
    expect(
      [
        summary.identityInvalid,
        summary.networkInvalid,
        summary.itemKindsInvalid,
        summary.periodicalsInvalid,
        summary.publishStateInvalid,
      ],
      everyElement(isFalse),
      reason: 'every additive entry of the file is readable',
    );

    // --- the additive entries, parsed for the controller to adopt ---
    expect(summary.restoredIdentity, (
      id: 'f1e2d3c4b5a69788f1e2d3c4b5a69788',
      name: 'Fixture Library',
    ));
    expect(
      [
        for (final row in summary.restoredNetwork!)
          '${row.siteUrl}|${row.name}|${row.source.name}|${row.isMember}',
      ],
      [
        'https://hub.github.io/x/||bookmark|false',
        'https://m.github.io/x/|Member Library|card|true',
      ],
    );
    final publishState = summary.restoredPublishState!;
    expect(publishState.coverSalt, archiveSalt);
    expect(
      publishState.verifiedTarget!.isSameExactTarget(archiveGitHub),
      isTrue,
    );
    expect(publishState.gitHubRecord.coverUrlByBookId, {
      '1': 'covers/0b1f-uuid.jpg',
      '2': 'https://covers.openlibrary.org/b/id/1-L.jpg',
    });

    // --- catalogue items: every stored field; ids too (loans use them) ---
    final items = _unwrap(await (await h.currentBooks()).getAll());
    final byUid = {for (final item in items) item.itemUid!: item};
    expect(byUid, hasLength(5));

    expect(_itemFields(byUid['fixture-book-1']!), {
      'id': 1,
      'itemUid': 'fixture-book-1',
      'title': 'गोदान',
      'titleTransliteration': 'Godaan',
      'author': 'प्रेमचंद',
      'isbn': '9780306406157',
      'publisher': 'Saraswati Press',
      'publishedYear': 1936,
      'genre': 'Novel',
      'coverUrl': 'covers/0b1f-uuid.jpg',
      'pageCount': 368,
      'language': 'हिंदी',
      'notes': 'First shelf copy',
      'location': 'Shelf 1',
      'sourceType': ItemSourceType.purchased,
      'sourceDetail': 'Book fair',
      'ageGroup': AgeGroup.above10,
      'addedDate': 100,
      'copyCount': 2,
      'needsMetadata': false,
      'removed': false,
      'removedAt': null,
      'addedBy': 'meera',
      'kind': 'book',
    });
    expect(byUid['fixture-book-1']!.details, isNull);

    // An issue carries six fields copied from its magazine title (name,
    // transliteration, publisher, language, year, age group; ADR 0013 D3).
    final issue = byUid['fixture-issue-1']!;
    expect(
      _itemFields(issue),
      _itemWith({
        'id': 2,
        'itemUid': 'fixture-issue-1',
        'title': 'चंदामामा — Vol 2 No 7 (Jan 2026)',
        'titleTransliteration': 'Chandamama — Vol 2 No 7 (Jan 2026)',
        'publisher': 'Chandamama India',
        'publishedYear': 2026,
        'language': 'हिंदी',
        'ageGroup': AgeGroup.above6,
        'addedDate': 200,
        'kind': 'magazineIssue',
      }),
    );
    expect(
      issue.details!.sameAs(
        const IssueOf(
          periodicalUid: 'fixture-series-1',
          volume: 2,
          issueNumber: 7,
          issueDate: 1767225600000,
          label: 'सर्दियों',
        ),
      ),
      isTrue,
    );

    final bound = byUid['fixture-bound-1']!;
    expect(
      _itemFields(bound),
      _itemWith({
        'id': 3,
        'itemUid': 'fixture-bound-1',
        'title': 'चंदामामा — Jan 2025 – Dec 2025',
        'titleTransliteration': 'Chandamama — Jan 2025 – Dec 2025',
        'publisher': 'Chandamama India',
        'publishedYear': 2025,
        'language': 'हिंदी',
        'ageGroup': AgeGroup.above6,
        'addedDate': 300,
        'removed': true,
        'removedAt': 301,
        'kind': 'magazineIssue',
      }),
    );
    expect(
      bound.details!.sameAs(
        const IssueOf(
          periodicalUid: 'fixture-series-1',
          issueDate: 1735689600000,
          boundUntil: 1764547200000,
          label: 'Annual 2025',
        ),
      ),
      isTrue,
    );

    final other = byUid['fixture-other-1']!;
    expect(
      _itemFields(other),
      _itemWith({
        'id': 4,
        'itemUid': 'fixture-other-1',
        'title': 'कैरम बोर्ड',
        'language': 'हिंदी',
        'ageGroup': AgeGroup.above10,
        'addedDate': 400,
        'kind': 'other',
      }),
    );
    expect(other.details, isA<OtherItemOf>());

    final remote = byUid['fixture-book-2']!;
    expect(
      _itemFields(remote),
      _itemWith({
        'id': 5,
        'itemUid': 'fixture-book-2',
        'title': 'Train to Pakistan',
        'author': 'Khushwant Singh',
        'coverUrl': 'https://covers.openlibrary.org/b/id/456-L.jpg',
        'addedDate': 500,
        'needsMetadata': true,
      }),
    );
    expect(remote.details, isNull);

    // --- magazine titles ---
    final periodicals = await h.container.read(
      periodicalRepositoryProvider.future,
    );
    final series = {
      for (final s in _unwrap(await periodicals.listAll()))
        s.periodical.periodicalUid!: s,
    };
    expect(series, hasLength(2));
    expect(_periodicalFields(series['fixture-series-1']!.periodical), {
      'periodicalUid': 'fixture-series-1',
      'title': 'चंदामामा',
      'titleTransliteration': 'Chandamama',
      'issn': '0577-6058',
      'publisher': 'Chandamama India',
      'language': 'हिंदी',
      'coverUrl': 'covers/series-local.jpg',
      'frequency': 'monthly',
      'subscriptionStart': 1767225600000,
      'subscriptionEnd': 1798761600000,
      'notes': 'Subscription note',
      'location': 'Shelf 2',
      'sourceType': ItemSourceType.purchased,
      'sourceDetail': 'Gift shop',
      'ageGroup': AgeGroup.above6,
      'addedDate': 10,
      'removed': false,
      'removedAt': null,
      'addedBy': 'meera',
    });
    // Both issue rows belong to this title; a removed issue still counts.
    expect(series['fixture-series-1']!.issueCount, 2);
    expect(series['fixture-series-2']!.issueCount, 0);
    final removedSeries = series['fixture-series-2']!.periodical;
    expect(removedSeries.title, 'Old Magazine');
    expect(
      removedSeries.coverUrl,
      'https://covers.openlibrary.org/b/id/123-L.jpg',
    );
    expect(removedSeries.addedDate, 20);
    expect(removedSeries.removed, isTrue);
    expect(removedSeries.removedAt, 21);

    // --- wishlist ---
    final wishlist = await h.container.read(wishlistRepositoryProvider.future);
    final wishes = {
      for (final w in _unwrap(await wishlist.getAll())) w.title: w,
    };
    expect(wishes, hasLength(2));
    expect(_wishFields(wishes['A Suitable Boy']!), {
      'title': 'A Suitable Boy',
      'titleTransliteration': 'A Suitable Boy',
      'author': 'Vikram Seth',
      'isbn': null,
      'publisher': 'Phoenix',
      'publishedYear': 1993,
      'coverUrl': null,
      'priceEstimate': 899.5,
      'priority': WishlistBook.priorityHigh,
      'notes': 'Ask at the book fair',
      'source': WishlistSource.manual,
      'addedDate': 600,
      'purchased': false,
      'purchasedDate': null,
      'needsMetadata': false,
    });
    expect(_wishFields(wishes['मैला आँचल']!), {
      'title': 'मैला आँचल',
      'titleTransliteration': null,
      'author': 'फणीश्वरनाथ रेणु',
      'isbn': null,
      'publisher': null,
      'publishedYear': null,
      'coverUrl': null,
      'priceEstimate': null,
      'priority': WishlistBook.priorityLow,
      'notes': null,
      'source': WishlistSource.manual,
      'addedDate': 700,
      'purchased': true,
      'purchasedDate': 800,
      'needsMetadata': true,
    });

    // --- covers: exactly the two pictures, byte for byte ---
    final covers = Directory(await h.coversDir());
    final coverNames = [
      for (final f in covers.listSync().whereType<File>())
        f.uri.pathSegments.last,
    ]..sort();
    expect(coverNames, ['0b1f-uuid.jpg', 'series-local.jpg']);
    for (final name in coverNames) {
      expect(
        File('${covers.path}/$name').readAsBytesSync(),
        File('$_fixtureDir/released_1_9_7_covers/$name').readAsBytesSync(),
        reason: name,
      );
    }

    // --- the vault pair of the file is now this device's vault ---
    final store = await h.currentStore();
    expect(
      File(store.dbPath).readAsBytesSync(),
      File('test/fixtures/vault/test_borrowers.db').readAsBytesSync(),
    );
    expect(
      store.readBlob(),
      File('test/fixtures/vault/test_backup_blob').readAsStringSync().trim(),
    );
  });
}
