import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/infrastructure/drift_periodical_repository.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/raw_catalogue_rows.dart';
import '../library/replacement_harness.dart';

T _unwrap<T>(Either<Failure, T> result) =>
    result.getOrElse((failure) => fail('Expected success, got: $failure'));

/// S11 §2 interchange verification through the app's real Drift repositories,
/// backup use case/writer, generation switch, and restore reader. The vault is
/// deliberately the existing fake: its bytes are opaque ciphertext, while its
/// domain rows let restore perform the real cross-DB loan integrity check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late ReplacementHarness h;

  setUp(() => h = ReplacementHarness(generations: true));
  tearDown(() => h.close());

  test(
    'writer-to-restore preserves the S11 catalogue, covers, and loans',
    () async {
      const localUid = 'पत्रिका-१';
      const legacyUid = 'पुरानी-पत्रिका-२';
      const paddedLegacyUid = '  पुरानी-पत्रिका-२  ';
      const localCover = 'covers/series-local.jpg';
      const remoteCover = 'https://covers.openlibrary.org/b/id/123-L.jpg';
      const bookUid = 'पुस्तक-१';
      const issueUid = 'संख्या-७';
      const boundUid = 'बाउन्ड-२';
      const otherUid = 'अन्य-१';

      final periodicals = DriftPeriodicalRepository(h.db);
      final localSeries = _unwrap(
        await periodicals.insert(
          const Periodical(
            title: 'चंदामामा',
            periodicalUid: localUid,
            titleTransliteration: 'Chandamama',
            issn: '0577-6058',
            publisher: 'Chandamama India',
            language: 'हिंदी',
            coverUrl: localCover,
            frequency: PeriodicalFrequency.monthly,
            subscriptionStart: 1767225600000,
            subscriptionEnd: 1798761600000,
            notes: 'Private subscription note',
            location: 'Shelf 2',
            sourceType: ItemSourceType.purchased,
            sourceDetail: 'Gift shop',
            ageGroup: AgeGroup.above6,
            addedDate: 10,
            addedBy: 'meera',
          ),
        ),
      );

      // A pre-v6 row is seeded below the mapper on purpose: current persistence
      // trims this UID, but an old device could still hand backup padded soft
      // links. Both the series and its issue must canonicalize to ONE restored
      // identity without losing the non-ASCII text.
      final legacySeriesId = await h.db
          .into(h.db.periodicals)
          .insert(
            PeriodicalsCompanion.insert(
              periodicalUid: paddedLegacyUid,
              title: 'पुरानी पत्रिका',
              coverUrl: const Value(remoteCover),
              addedDate: 20,
              removed: const Value(true),
              removedAt: const Value(21),
            ),
          );
      final legacySeries = _unwrap(await periodicals.getById(legacySeriesId))!;

      final book = _unwrap(
        await h.books.insert(
          const CatalogueItem(
            itemUid: bookUid,
            title: 'गोदान',
            author: 'प्रेमचंद',
            language: 'हिंदी',
            copyCount: 2,
            addedDate: 100,
          ),
        ),
      );

      final numberedIssueId = await seedRawCatalogueRow(
        h.db,
        title: 'पुरानी पत्रिका — Vol 2 No 7',
        kind: 'magazine-issue',
        itemUid: issueUid,
        addedDate: 200,
      );
      await h.db
          .into(h.db.magazineIssues)
          .insert(
            MagazineIssuesCompanion.insert(
              itemId: Value(numberedIssueId),
              periodicalUid: paddedLegacyUid,
              volume: const Value(2),
              issueNumber: const Value(7),
              issueDate: const Value(1767225600000),
              issueLabel: const Value('सर्दियों'),
            ),
          );

      final bound = _unwrap(
        await h.books.insert(
          const CatalogueItem(
            itemUid: boundUid,
            title: 'चंदामामा — 2025 bound volume',
            addedDate: 300,
            removed: true,
            removedAt: 301,
            details: IssueOf(
              periodicalUid: localUid,
              issueDate: 1735689600000,
              boundUntil: 1764547200000,
              label: 'Annual 2025',
            ),
          ),
        ),
      );
      final other = _unwrap(
        await h.books.insert(
          const CatalogueItem(
            itemUid: otherUid,
            title: 'कैरम बोर्ड',
            language: 'हिंदी',
            ageGroup: AgeGroup.above10,
            addedDate: 400,
            details: OtherItemOf(),
          ),
        ),
      );
      expect(other.kind, ItemKind.other);

      h.vault.borrowers = [const Borrower(id: 1, name: 'Asha')];
      h.vault.loans.addAll([
        Loan(
          id: 1,
          itemId: book.id,
          borrowerId: 1,
          lentDate: 500,
          dueDate: 600,
          notes: 'Still out',
        ),
        Loan(
          id: 2,
          itemId: bound.id,
          borrowerId: 1,
          lentDate: 700,
          returnedDate: 800,
        ),
      ]);
      await h.initialize();

      final sourceCovers = await h.coversDir();
      Directory(sourceCovers).createSync(recursive: true);
      File(
        '$sourceCovers/series-local.jpg',
      ).writeAsBytesSync(const [1, 3, 3, 7], flush: true);
      final originalVaultBytes = File(h.store.dbPath).readAsBytesSync();
      const originalBlob = 'synthetic.blob.only';

      final create = await h.container.read(createBackupUseCaseProvider.future);
      final backup = _unwrap(await create());
      expect(backup.bytes, isNotEmpty);

      // Make restore prove its input came from the archive, not from surviving
      // live state. The changed live vault must also be replaced by the
      // archived ciphertext pair after the fake validates the staged DB bytes.
      await h.db.delete(h.db.books).go();
      await h.db.delete(h.db.periodicals).go();
      Directory(sourceCovers).deleteSync(recursive: true);
      File(h.store.dbPath).writeAsBytesSync(const [9, 9, 9]);
      h.store.writeBlob('changed.live.blob');
      var sawArchivedVault = false;
      h.vault.onRead = () async {
        sawArchivedVault = true;
        expect(
          File(
            '${h.directory.path}/restore_work/borrowers.db',
          ).readAsBytesSync(),
          originalVaultBytes,
        );
      };

      final restorer = await h.container.read(restoreBackupProvider.future);
      final passphrase = ReplacementHarness.secret();
      final result = await restorer.restore(
        archiveBytes: backup.bytes,
        passphrase: passphrase,
      );
      passphrase.dispose();
      final summary = _unwrap(result);

      expect(sawArchivedVault, isTrue);
      expect(summary.booksRestored, 4);
      expect(summary.periodicalsRestored, 2);
      expect(summary.kindsApplied, 3);
      expect(summary.issuesLinked, 2);
      expect(summary.issuesDetached, 0);
      expect(summary.issueEntriesDropped, 0);
      expect(summary.periodicalsDropped, 0);
      expect(summary.coversDropped, 0);
      expect(summary.borrowersRestored, 1);
      expect(summary.loansRestored, 2);
      expect(summary.danglingLoans, isEmpty);
      expect(summary.isIntact, isTrue);

      final restoredItems = _unwrap(await (await h.currentBooks()).getAll());
      final byUid = {for (final item in restoredItems) item.itemUid!: item};
      expect(byUid.keys, containsAll([bookUid, issueUid, boundUid, otherUid]));
      expect(byUid, hasLength(4));

      final restoredBook = byUid[bookUid]!;
      expect(
        restoredBook.id,
        book.id,
        reason: 'the active loan keeps its link',
      );
      expect(restoredBook.title, 'गोदान');
      expect(restoredBook.author, 'प्रेमचंद');
      expect(restoredBook.copyCount, 2);
      expect(restoredBook.kind, ItemKind.book);

      final numbered = byUid[issueUid]!;
      expect(numbered.kind, ItemKind.magazineIssue);
      expect(
        numbered.issue!.sameAs(
          const IssueOf(
            periodicalUid: legacyUid,
            volume: 2,
            issueNumber: 7,
            issueDate: 1767225600000,
            label: 'सर्दियों',
          ),
        ),
        isTrue,
      );

      final restoredBound = byUid[boundUid]!;
      expect(restoredBound.id, bound.id, reason: 'loan history keeps its link');
      expect(restoredBound.issue!.isBound, isTrue);
      expect(restoredBound.issue!.boundUntil, 1764547200000);
      expect(restoredBound.removed, isTrue);
      expect(restoredBound.removedAt, 301);
      expect(byUid[otherUid]!.kind, ItemKind.other);
      expect(byUid[otherUid]!.details, isA<OtherItemOf>());

      final currentPeriodicals = await h.container.read(
        periodicalRepositoryProvider.future,
      );
      final restoredPeriodicals = _unwrap(await currentPeriodicals.listAll());
      expect(restoredPeriodicals, hasLength(2));
      final seriesByUid = {
        for (final summary in restoredPeriodicals)
          summary.periodical.periodicalUid!: summary,
      };
      expect(
        seriesByUid[localUid]!.periodical.sameAs(localSeries),
        isTrue,
        reason: 'the local cover and every series attribute survive',
      );
      expect(seriesByUid[localUid]!.issueCount, 1);
      final restoredLegacy = seriesByUid[legacyUid]!;
      expect(
        restoredLegacy.periodical.sameAs(
          legacySeries.copyWith(periodicalUid: legacyUid),
        ),
        isTrue,
        reason:
            'padding is removed; non-ASCII identity and remote cover remain',
      );
      expect(restoredLegacy.periodical.removed, isTrue);
      expect(restoredLegacy.periodical.removedAt, 21);
      expect(restoredLegacy.periodical.coverUrl, remoteCover);
      expect(restoredLegacy.issueCount, 1);

      final restoredCovers = await h.coversDir();
      expect(restoredCovers, isNot(sourceCovers));
      expect(File('$restoredCovers/series-local.jpg').readAsBytesSync(), const [
        1,
        3,
        3,
        7,
      ]);
      final restoredStore = await h.currentStore();
      expect(File(restoredStore.dbPath).readAsBytesSync(), originalVaultBytes);
      expect(restoredStore.readBlob(), originalBlob);
    },
  );

  for (final rawKind in ['hologram', 'magazine-issue']) {
    test('backup creation fails closed on raw $rawKind corruption', () async {
      final id = await seedRawCatalogueRow(
        h.db,
        title: 'Raw $rawKind',
        kind: rawKind,
        itemUid: 'raw-$rawKind',
        coverUrl: 'covers/raw.jpg',
      );
      final create = await h.container.read(createBackupUseCaseProvider.future);
      final result = await create();

      final failure = result.getLeft().toNullable();
      if (rawKind == 'hologram') {
        expect(failure, isA<UnsupportedItemKindFailure>());
      } else {
        expect(failure, isA<StorageFailure>());
      }
      expect(result.toNullable(), isNull);
      expect(
        Directory('${h.directory.path}/backup_create_work').existsSync(),
        isFalse,
        reason: 'the strict Drift read refuses before writer scratch work',
      );
      final raw = await (h.db.select(
        h.db.books,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(raw.kind, rawKind);
      expect(raw.title, 'Raw $rawKind');
      expect(raw.coverUrl, 'covers/raw.jpg');
    });
  }
}
