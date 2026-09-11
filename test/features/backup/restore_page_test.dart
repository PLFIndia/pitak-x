/// N13 widget tests (astra-review.md): the Restore screen must inspect the
/// archive's bounded manifest FIRST and only ask for a passphrase when the
/// backup actually carries an encrypted vault. A vault-free backup used to
/// demand a password the user never created.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// Transitive dependency of file_selector; imported only for the picker seam
// below (it also re-exports XFile). Deliberately NOT added to pubspec so the
// dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';

import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';
import 'generation_fixture.dart';

class _RetainedRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    existingVaultKept: true,
  );
}

class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

/// Picker seam: hands back an in-memory [XFile] (no file IO, so the test's
/// FakeAsync zone never blocks).
class _FakeFileSelector extends FileSelectorPlatform {
  _FakeFileSelector(this.bytes, {this.reportedLength});
  final Uint8List bytes;

  /// M05: lets a test hand the page a file whose reported size differs from
  /// its real bytes (a huge declared length without allocating it).
  final int? reportedLength;
  int picks = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    picks++;
    return XFile.fromData(bytes, name: 'test.pitabak', length: reportedLength);
  }
}

/// N04: a controller whose inspect/restore always succeed (vault-free), so
/// the page's post-success refresh path runs without the restorer machinery.
class _SuccessController extends RestoreController {
  @override
  RestoreSummary? build() => null;

  @override
  Future<Either<Failure, BackupManifest>> inspectArchive(
    Uint8List archiveBytes,
  ) async => right(
    const BackupManifest(
      exportedAt: 123,
      hasBorrowers: false,
      hasBackupBlob: false,
    ),
  );

  @override
  Future<void> restore({
    required Uint8List archiveBytes,
    SecretBytes? passphrase,
  }) async {
    state = const AsyncData(
      RestoreSummary(
        booksRestored: 1,
        wishlistRestored: 1,
        borrowersRestored: 0,
        loansRestored: 0,
        existingVaultKept: true,
      ),
    );
  }
}

/// Counts `getAll` calls so the test can prove the wishlist was re-read.
class _CountingWishlistRepo extends DriftWishlistRepository {
  _CountingWishlistRepo(super.db);

  int getAllCalls = 0;

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() {
    getAllCalls++;
    return super.getAll();
  }
}

/// Minimal in-memory settings repo (the library controller watches the sort).
class _SettingsRepoStub implements SettingsRepository {
  AppSettings settings = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async =>
      right(unit);
  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async =>
      right('a' * 32);
  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async => right(unit);
  @override
  Future<Either<Failure, String>> regenerateLibraryId() async =>
      right('b' * 32);
  @override
  Future<Either<Failure, Unit>> setMaintainerName(String name) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);
}

Uint8List _archive({required bool withVault, int exportedAt = 123}) {
  final manifest = jsonEncode({
    'schemaVersion': 1,
    'exportedAt': exportedAt,
    'hasBooks': true,
    'hasWishlist': true,
    'hasBorrowers': withVault,
    'hasBackupBlob': withVault,
    'hasCovers': false,
  });
  final a = Archive()
    ..addFile(
      ArchiveFile('manifest.json', manifest.length, utf8.encode(manifest)),
    );
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late GenerationFixture gen;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_page_test');
    // M02: the restorer works on a real on-disk data generation.
    gen = GenerationFixture(tmp);
  });

  tearDown(() async {
    await gen.db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(
    Uint8List archiveBytes, {
    Failure? replacementFailure,
    int? reportedLength,
  }) {
    final restorer = gen.restorer(
      vault: _FakeVault(),
      guard: FakeReplacementGuard(failure: replacementFailure),
    );
    FileSelectorPlatform.instance = _FakeFileSelector(
      archiveBytes,
      reportedLength: reportedLength,
    );
    return ProviderScope(
      overrides: [
        restoreBackupProvider.overrideWith((ref) async => restorer),
        vaultStoreProvider.overrideWith((ref) async => gen.store),
      ],
      child: const MaterialApp(home: RestorePage()),
    );
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Choose .pitabak file'));
    await tester.pumpAndSettle();
  }

  testWidgets('vault-free backup: no passphrase asked, Restore enabled', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_archive(withVault: false)));

    // Before picking: nothing to restore.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await pick(tester);

    // The manifest summary says there is no vault...
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    // ...so no passphrase field is shown...
    expect(find.text('Passphrase'), findsNothing);
    expect(find.textContaining('no passphrase is needed'), findsOneWidget);
    // ...and Restore is enabled immediately.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('M03: refusal is shown before any restore work', (tester) async {
    await tester.pumpWidget(
      wrap(
        _archive(withVault: false),
        replacementFailure: const ValidationFailure(
          'Unlock the borrowers vault first.',
        ),
      ),
    );
    expect(
      find.textContaining('every book link can be matched safely'),
      findsOneWidget,
    );
    await pick(tester);
    await tester.ensureVisible(find.text('Restore'));
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock the borrowers vault first.'), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);
    expect(Directory('${tmp.path}/restore_work').existsSync(), isFalse);
  });

  testWidgets('M03: retained-vault success reports preserved history', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restoreControllerProvider.overrideWith(
            _RetainedRestoreController.new,
          ),
        ],
        child: const MaterialApp(home: RestorePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('including returned loan history'),
      findsOneWidget,
    );
    expect(find.textContaining('may no longer match'), findsNothing);
  });

  testWidgets('vault backup: passphrase required before Restore enables', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_archive(withVault: true)));
    await pick(tester);

    expect(
      find.textContaining('encrypted — passphrase required'),
      findsOneWidget,
    );
    expect(find.text('Passphrase'), findsOneWidget);
    // Disabled while the passphrase is empty...
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    // ...enabled once something was entered.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('an unreadable file is rejected before any restore', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(Uint8List.fromList([9, 9, 9])));
    await pick(tester);

    expect(
      find.textContaining('doesn’t look like a valid Pitak backup'),
      findsOneWidget,
    );
    // The bad file was dropped: Restore stays disabled, no passphrase field.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    expect(find.text('Passphrase'), findsNothing);
  });

  testWidgets('M05: an oversized pick is refused before it is read', (
    tester,
  ) async {
    // A perfectly valid archive whose picker-reported size is 5 GiB. The
    // page must refuse on the report alone: no bytes buffered, no
    // inspection, nothing to restore.
    await tester.pumpWidget(
      wrap(_archive(withVault: false), reportedLength: 5 * 1024 * 1024 * 1024),
    );
    await pick(tester);

    expect(find.textContaining('too large'), findsOneWidget);
    expect(find.text('Choose .pitabak file'), findsOneWidget);
    expect(find.textContaining('No borrowers vault'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    // Picking a sane file afterwards clears the error and proceeds normally.
    FileSelectorPlatform.instance = _FakeFileSelector(
      _archive(withVault: false),
    );
    await pick(tester);
    expect(find.textContaining('too large'), findsNothing);
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
  });

  testWidgets('M15: an out-of-range manifest exportedAt renders without a '
      'date instead of throwing', (tester) async {
    // The manifest is untrusted: exportedAt above DateTime's range used to
    // throw RangeError inside _ManifestSummary.build on INSPECT, before any
    // passphrase or restore.
    await tester.pumpWidget(
      wrap(_archive(withVault: false, exportedAt: 8640000000000001)),
    );
    await pick(tester);

    // The page renders the summary; the date line is simply absent.
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    expect(find.textContaining('Made on:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N04: a successful restore refreshes the wishlist too', (
    tester,
  ) async {
    // Restore replaces books AND the wishlist (M15), but the page used to
    // refresh only the library list — a mounted wishlist tab kept showing
    // pre-restore rows until restart.
    final wishlist = _CountingWishlistRepo(gen.db);
    final container = ProviderContainer(
      overrides: [
        restoreControllerProvider.overrideWith(_SuccessController.new),
        bookRepositoryProvider.overrideWith(
          (ref) async => DriftBookRepository(gen.db),
        ),
        settingsRepositoryProvider.overrideWith(
          (ref) async => _SettingsRepoStub(),
        ),
        wishlistRepositoryProvider.overrideWith((ref) async => wishlist),
      ],
    );
    addTearDown(container.dispose);
    FileSelectorPlatform.instance = _FakeFileSelector(
      _archive(withVault: false),
    );

    // Mounted tabs keep both list controllers alive, like the real shell.
    final wishlistSub = container.listen(
      wishlistControllerProvider,
      (_, __) {},
    );
    final librarySub = container.listen(libraryControllerProvider, (_, __) {});
    addTearDown(wishlistSub.close);
    addTearDown(librarySub.close);
    await container.read(wishlistControllerProvider.future);
    expect(wishlist.getAllCalls, 1);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RestorePage()),
      ),
    );
    await pick(tester);
    await tester.ensureVisible(find.text('Restore'));
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Restore complete'), findsOneWidget);
    // Initial load + the post-restore refresh.
    expect(wishlist.getAllCalls, 2);
  });
}
