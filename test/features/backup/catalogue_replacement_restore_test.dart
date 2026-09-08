import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../library/replacement_harness.dart';

/// Hook into the BUILDER generation's catalogue (M02: restore writes there,
/// never into the live one) so a test can inject a fault or a lock right
/// after the rows were written.
class _RestoreHooks {
  Future<void> Function()? afterRebuild;

  AppDatabase open(String path) => _RestoreDb(this, NativeDatabase(File(path)));
}

class _RestoreDb extends AppDatabase {
  _RestoreDb(this._hooks, super.executor);
  final _RestoreHooks _hooks;
  @override
  Future<void> rebuildFts() async {
    await super.rebuildFts();
    await _hooks.afterRebuild?.call();
  }
}

const _book = Book(id: 7, bookUid: 'stable', title: 'Existing');
const _loan = Loan(id: 1, bookId: 7, borrowerId: 1, lentDate: 1);

void main() {
  late ReplacementHarness h;
  late _RestoreHooks hooks;
  setUp(() {
    hooks = _RestoreHooks();
    // M03 policy C on the REAL M02 storage chain: session guard, generation
    // switch, and post-restore reads through the providers the app uses.
    h = ReplacementHarness(generations: true, openCatalogue: hooks.open);
  });
  tearDown(() => h.close());

  Uint8List archive(List<Book> incoming) =>
      BackupArchiveWriter(
        openDatabase: sqlite3.open,
        vaultStore: VaultStore(baseDir: '${h.directory.path}/no_source_vault'),
        coversDir: '${h.directory.path}/incoming_covers',
      ).build(
        books: incoming,
        wishlist: [],
        workDir: '${h.directory.path}/build_archive',
        exportedAt: 1,
      );

  Future<void> existing({bool returned = false}) async {
    await h.books.insert(_book);
    h.vault.loans.add(returned ? _loan.copyWith(returnedDate: 2) : _loan);
    await h.initialize();
  }

  for (final returned in [false, true]) {
    test(
      'vault-free restore preserves ${returned ? 'returned' : 'active'} links',
      () async {
        await existing(returned: returned);
        final restorer = await h.container.read(restoreBackupProvider.future);
        final bytes = archive([
          const Book(id: 7, bookUid: 'new', title: 'New'),
          _book.copyWith(id: 99, title: 'Changed'),
        ]);
        final result = await restorer.restore(archiveBytes: bytes);
        expect(result.isRight(), isTrue);
        final summary = result.toNullable()!;
        expect(summary.existingVaultKept, isTrue);
        expect(summary.isIntact, isTrue);
        expect(summary.borrowersRestored, 0);
        final books = await h.currentBooks();
        expect((await books.getById(7)).toNullable()!.title, 'Changed');
        expect((await books.getAll()).toNullable()!.length, 2);
        expect(h.vault.loans.single.bookId, 7);
        expect(h.vault.writes, 0);
        // The retained vault moved with the catalogue into the new generation.
        final store = await h.currentStore();
        expect(store.baseDir, isNot(h.store.baseDir));
        expect(File(store.dbPath).readAsBytesSync(), [1, 2, 3]);
        expect(store.readBlob(), 'synthetic.blob.only');
        // M02: the session was ended by the switch; a retained vault must be
        // unlocked again before the next replacement can verify its loans.
        expect(h.session.isUnlocked, isFalse);
        expect((await restorer.restore(archiveBytes: bytes)).isLeft(), isTrue);
        await h.session.unlock(ReplacementHarness.secret());
        expect((await restorer.restore(archiveBytes: bytes)).isRight(), isTrue);
        final again = await h.currentBooks();
        expect((await again.getById(7)).toNullable()!.bookUid, 'stable');
      },
    );
  }

  test(
    'same-ID substitution refuses and leaves all stores and covers intact',
    () async {
      await existing();
      await h.db
          .into(h.db.wishlistBooks)
          .insert(
            WishlistBooksCompanion.insert(title: 'Wishlist', addedDate: 1),
          );
      final cover = File('${await h.coversDir()}/old.jpg');
      cover.parent.createSync(recursive: true);
      cover.writeAsBytesSync([9, 9]);
      final source = File('${h.directory.path}/incoming_covers/new.jpg');
      source.parent.createSync(recursive: true);
      source.writeAsBytesSync([8, 8]);
      final restorer = await h.container.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archiveBytes: archive([
          const Book(id: 7, bookUid: 'unrelated', title: 'Other'),
        ]),
      );
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      final books = await h.currentBooks();
      expect((await books.getById(7)).toNullable()!.title, 'Existing');
      expect(
        (await h.db.select(h.db.wishlistBooks).get()).single.title,
        'Wishlist',
      );
      expect(cover.readAsBytesSync(), [9, 9]);
      expect(File('${await h.coversDir()}/new.jpg').existsSync(), isFalse);
      // No generation switch happened; the same store is still the live one.
      expect((await h.currentStore()).baseDir, h.store.baseDir);
    },
  );

  test(
    'lock after writes but before transaction end rolls everything back',
    () async {
      await existing();
      hooks.afterRebuild = () => h.session.lock();
      final restorer = await h.container.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archiveBytes: archive([_book.copyWith(id: 99, title: 'Changed')]),
      );
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      final books = await h.currentBooks();
      expect((await books.getById(7)).toNullable()!.title, 'Existing');
      expect(h.vault.writes, 0);
      expect((await h.currentStore()).baseDir, h.store.baseDir);
    },
  );

  test(
    'FTS failure after remapping rolls back without changing vault',
    () async {
      await existing();
      hooks.afterRebuild = () async =>
          throw StateError('synthetic FTS failure');
      final restorer = await h.container.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archiveBytes: archive([_book.copyWith(id: 99, title: 'Changed')]),
      );
      expect(result.getLeft().toNullable(), isA<StorageFailure>());
      final books = await h.currentBooks();
      expect((await books.getById(7)).toNullable()!.title, 'Existing');
      expect(File(h.store.dbPath).readAsBytesSync(), [1, 2, 3]);
      expect((await h.currentStore()).baseDir, h.store.baseDir);
    },
  );

  test(
    'locked existing vault refuses, then unlock and retry succeeds',
    () async {
      await existing();
      await h.session.lock();
      final restorer = await h.container.read(restoreBackupProvider.future);
      final bytes = archive([_book.copyWith(id: 99)]);
      expect((await restorer.restore(archiveBytes: bytes)).isLeft(), isTrue);
      expect(
        Directory('${h.directory.path}/restore_work').existsSync(),
        isFalse,
      );
      await h.session.unlock(ReplacementHarness.secret());
      expect((await restorer.restore(archiveBytes: bytes)).isRight(), isTrue);
    },
  );

  test('empty backup cannot erase books referenced by loan history', () async {
    await existing(returned: true);
    final restorer = await h.container.read(restoreBackupProvider.future);
    expect(
      (await restorer.restore(archiveBytes: archive([]))).isLeft(),
      isTrue,
    );
    final books = await h.currentBooks();
    expect((await books.getAll()).toNullable()!.single.id, 7);
  });
}
