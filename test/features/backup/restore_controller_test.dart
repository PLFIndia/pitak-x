import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';

import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';
import 'generation_fixture.dart';

/// Fake vault: never loads the native lib. Returns empty data (unused in the
/// corrupt-archive path, but required by the RestoreBackup constructor).
class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

/// In-memory settings repo that records logo writes (N04 logo-hygiene tests).
class _LogoSettingsRepo implements SettingsRepository {
  AppSettings settings = AppSettings.defaults;

  /// Every reference passed to setLibraryLogo, in order.
  final List<String> logoWrites = [];

  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) async {
    logoWrites.add(reference);
    settings = settings.copyWith(libraryLogo: reference);
    return right(unit);
  }

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
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_ctrl_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// The REAL storage chain (M02): docs dir → data generations → active
  /// generation → database / covers / vault store → restorer. Only the Rust
  /// vault is faked. This is what proves the whole app follows a generation
  /// switch, not just the restorer.
  ProviderContainer makeContainer({SettingsRepository? settings}) {
    final container = ProviderContainer(
      overrides: [
        appDocsDirProvider.overrideWith((ref) async => tmp),
        vaultRepositoryProvider.overrideWithValue(_FakeVault()),
        if (settings != null)
          settingsRepositoryProvider.overrideWith((ref) async => settings),
      ],
    );
    addTearDown(() async {
      // Close whatever catalogue the chain opened before deleting the files.
      if (container.exists(appDatabaseProvider)) {
        await (await container.read(appDatabaseProvider.future)).close();
      }
      container.dispose();
    });
    return container;
  }

  /// A minimal VALID archive that carries only a vault (no books/wishlist):
  /// manifest + backup_blob + borrowers.db. Restore installs the vault pair.
  Uint8List vaultOnlyArchive() {
    final manifest = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'exportedAt': 123,
        'hasBooks': false,
        'hasWishlist': false,
        'hasBorrowers': true,
        'hasBackupBlob': true,
        'hasCovers': false,
      }),
    );
    final blob = utf8.encode('blob-from-archive');
    final borrowersDb = utf8.encode('opaque-encrypted-db');
    final a = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('backup_blob', blob.length, blob))
      ..addFile(ArchiveFile('borrowers.db', borrowersDb.length, borrowersDb));
    return Uint8List.fromList(ZipEncoder().encode(a)!);
  }

  test('maps a corrupt archive to AsyncError(BackupCorruptFailure)', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([1, 2, 3]));

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]), // not a zip
          passphrase: passphrase,
        );

    final state = container.read(restoreControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<BackupCorruptFailure>());
  });

  test('disposes the passphrase after restore (success or failure)', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([9, 9, 9]));

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]),
          passphrase: passphrase,
        );

    // §6.1: the controller must wipe the secret; using it now must throw.
    expect(() => passphrase.use((b) => b), throwsStateError);
  });

  test('successful restore rebuilds the vault session (Create vault -> '
      'Unlock)', () async {
    final container = makeContainer();

    // Before restore: no vault on disk, so the session is Uninitialized —
    // this is the state that used to go STALE (keepAlive) after a restore.
    final before = await container.read(vaultSessionControllerProvider.future);
    expect(before, isA<VaultUninitialized>());

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: vaultOnlyArchive(),
          passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
        );
    expect(container.read(restoreControllerProvider).hasValue, isTrue);

    // The controller must invalidate the session so build() re-checks the
    // (now installed) vault files: Uninitialized -> Locked, i.e. the vault
    // page shows "Unlock" instead of "Create vault".
    final after = await container.read(vaultSessionControllerProvider.future);
    expect(after, isA<VaultLocked>());
  });

  test('failed restore leaves the vault session untouched', () async {
    final container = makeContainer();
    var rebuilds = 0;
    container.listen(
      vaultSessionControllerProvider,
      (_, _) => rebuilds++,
      fireImmediately: true,
    );
    await container.read(vaultSessionControllerProvider.future);
    final baseline = rebuilds;

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archiveBytes: Uint8List.fromList([0, 1, 2, 3]), // not a zip
          passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
        );

    expect(container.read(restoreControllerProvider).hasError, isTrue);
    // No invalidation on failure: nothing on disk changed, so no rebuild.
    expect(rebuilds, baseline);
    expect(
      await container.read(vaultSessionControllerProvider.future),
      isA<VaultUninitialized>(),
    );
  });

  // N13: the screen inspects the manifest before asking for a passphrase.
  test('inspectArchive surfaces the manifest without touching state', () async {
    final container = makeContainer();
    final inspected = await container
        .read(restoreControllerProvider.notifier)
        .inspectArchive(vaultOnlyArchive());
    final manifest = inspected.getOrElse((f) => fail('unexpected: $f'));
    expect(manifest.hasBackupBlob, isTrue);
    // Still idle — inspection is not a restore.
    expect(container.read(restoreControllerProvider).value, isNull);
  });

  test('a vault-free restore accepts a null passphrase', () async {
    final container = makeContainer();
    // Manifest with no vault + no books/wishlist rows: a valid empty restore.
    final manifest = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'exportedAt': 123,
        'hasBooks': false,
        'hasWishlist': false,
        'hasBorrowers': false,
        'hasBackupBlob': false,
        'hasCovers': false,
      }),
    );
    final a = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final zip = Uint8List.fromList(ZipEncoder().encode(a)!);

    await container
        .read(restoreControllerProvider.notifier)
        .restore(archiveBytes: zip); // N13: null passphrase, no crash

    final state = container.read(restoreControllerProvider);
    expect(state.hasValue, isTrue);
    expect(state.value?.booksRestored, 0);
  });

  group('N04 — dangling library-logo reference after restore (S9 note)', () {
    // Settings are NOT part of a backup, so a restore can leave the logo
    // reference pointing at a cover file the restored set does not have.
    // These archives carry no covers, so the device's set is carried over
    // verbatim — the logo file is present exactly when the test plants it.
    Uint8List emptyArchive() {
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 123,
          'hasBooks': false,
          'hasWishlist': false,
          'hasBorrowers': false,
          'hasBackupBlob': false,
          'hasCovers': false,
        }),
      );
      final a = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      return Uint8List.fromList(ZipEncoder().encode(a)!);
    }

    test('a dangling logo reference is cleared after a restore', () async {
      final settings = _LogoSettingsRepo()
        ..settings = AppSettings.defaults.copyWith(
          libraryLogo: 'covers/logo.jpg',
        );
      final container = makeContainer(settings: settings);
      await container.read(settingsControllerProvider.future);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archiveBytes: emptyArchive());

      expect(
        container.read(restoreControllerProvider).hasValue,
        isTrue,
        reason: 'the restore itself must succeed for the hygiene to run',
      );
      expect(settings.logoWrites, ['']);
      expect(
        container.read(settingsControllerProvider).valueOrNull?.libraryLogo,
        '',
      );
    });

    test('a logo whose file survived the restore is kept', () async {
      final settings = _LogoSettingsRepo()
        ..settings = AppSettings.defaults.copyWith(
          libraryLogo: 'covers/logo.jpg',
        );
      final container = makeContainer(settings: settings);
      await container.read(settingsControllerProvider.future);
      // Plant the referenced file in the ACTIVE generation's covers dir; a
      // covers-less archive carries the device's set over, so it survives.
      final coversDir = await container.read(coversDirProvider.future);
      Directory(coversDir).createSync(recursive: true);
      File(p.join(coversDir, 'logo.jpg')).writeAsBytesSync([1, 2, 3]);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archiveBytes: emptyArchive());

      expect(settings.logoWrites, isEmpty);
      expect(
        container.read(settingsControllerProvider).valueOrNull?.libraryLogo,
        'covers/logo.jpg',
      );
    });

    test('no logo set means no settings write', () async {
      final settings = _LogoSettingsRepo();
      final container = makeContainer(settings: settings);
      await container.read(settingsControllerProvider.future);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archiveBytes: emptyArchive());

      expect(settings.logoWrites, isEmpty);
    });
  });

  group('N11 — restore lifecycle ownership', () {
    /// Container wired like the page's harness: a real restorer over a real
    /// on-disk generation, gated so a test can park a restore mid-flight.
    ProviderContainer gatedContainer({required Completer<void> gate}) {
      final gen = GenerationFixture(tmp);
      addTearDown(() async => gen.db.close());
      final container = ProviderContainer(
        overrides: [
          restoreBackupProvider.overrideWith((ref) async {
            await gate.future;
            return gen.restorer(
              vault: _FakeVault(),
              guard: FakeReplacementGuard(),
            );
          }),
          vaultStoreProvider.overrideWith((ref) async => gen.store),
          vaultRepositoryProvider.overrideWithValue(_FakeVault()),
          settingsRepositoryProvider.overrideWith(
            (ref) async => _LogoSettingsRepo(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an in-flight restore keeps its terminal state when the page goes '
        'away', () async {
      // The page watches the controller; popping it removes the last
      // listener. Without a keep-alive link autoDispose disposes the element
      // mid-flight: the terminal state is swallowed and a re-entered page
      // sees a fresh IDLE controller while the restore still runs.
      final gate = Completer<void>();
      final container = gatedContainer(gate: gate);

      final sub = container.listen(restoreControllerProvider, (_, __) {});
      final future = container
          .read(restoreControllerProvider.notifier)
          .restore(
            archiveBytes: vaultOnlyArchive(),
            passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
          );
      expect(container.read(restoreControllerProvider).isLoading, isTrue);

      sub.close(); // the page is popped: last listener gone
      await container.pump(); // flush the scheduled autoDispose
      gate.complete();
      await future;

      // Read in the same microtask turn: the keep-alive link closed in the
      // finally schedules disposal on the NEXT event-loop turn (verified in
      // riverpod-2.6.1 scheduler: `_defaultVsync` = `Future(task)`), so the
      // element is still here.
      expect(
        container.read(restoreControllerProvider).value,
        isNotNull,
        reason: 'the terminal summary must survive navigation (keep-alive)',
      );
    });

    test('a second restore while one is in flight is refused', () async {
      // The other half of the hazard: without a re-entrancy guard a rebuilt
      // page (or a double-tap race) starts a SECOND restore over the one
      // still running.
      final gate = Completer<void>();
      final container = gatedContainer(gate: gate);
      final sub = container.listen(restoreControllerProvider, (_, __) {});
      addTearDown(sub.close);

      final first = container
          .read(restoreControllerProvider.notifier)
          .restore(
            archiveBytes: vaultOnlyArchive(),
            passphrase: SecretBytes(Uint8List.fromList([1])),
          );
      final refusedSecret = SecretBytes(Uint8List.fromList([2]));
      var secondDone = false;
      final second = container
          .read(restoreControllerProvider.notifier)
          .restore(archiveBytes: vaultOnlyArchive(), passphrase: refusedSecret)
          .then((_) => secondDone = true);
      await pumpEventQueue();

      expect(
        secondDone,
        isTrue,
        reason: 'a concurrent restore must be refused immediately, not queued',
      );
      // A refused call still wipes the secret it was handed (§6.1).
      expect(() => refusedSecret.use((b) => b), throwsStateError);

      gate.complete();
      await first;
      await second;
      expect(container.read(restoreControllerProvider).hasValue, isTrue);
    });

    test('an unexpected throw becomes AsyncError(UnexpectedFailure) and the '
        'passphrase is still wiped', () async {
      // A throwing plugin/provider must not escape into the page's unawaited
      // future — the controller owns a typed terminal state on EVERY path.
      final container = ProviderContainer(
        overrides: [
          restoreBackupProvider.overrideWith(
            (ref) async => throw StateError('plugin exploded'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final passphrase = SecretBytes(Uint8List.fromList([7]));

      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archiveBytes: Uint8List.fromList([0]),
            passphrase: passphrase,
          );

      final state = container.read(restoreControllerProvider);
      expect(state.error, isA<UnexpectedFailure>());
      expect(() => passphrase.use((b) => b), throwsStateError);
    });

    test('a successful restore invalidates the library and wishlist '
        'controllers', () async {
      // N04 behaviour, N11 ownership: the refresh used to be the page's job
      // (lost when the page was popped mid-restore); the controller owns it.
      final container = makeContainer(settings: _LogoSettingsRepo());
      var libraryBuilds = 0;
      var wishlistBuilds = 0;
      container
        ..listen(
          libraryControllerProvider,
          (_, __) => libraryBuilds++,
          fireImmediately: true,
        )
        ..listen(
          wishlistControllerProvider,
          (_, __) => wishlistBuilds++,
          fireImmediately: true,
        );
      await container.read(libraryControllerProvider.future);
      await container.read(wishlistControllerProvider.future);
      final libraryBaseline = libraryBuilds;
      final wishlistBaseline = wishlistBuilds;

      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archiveBytes: vaultOnlyArchive(),
            passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
          );
      expect(container.read(restoreControllerProvider).hasValue, isTrue);
      await container.pump(); // flush the invalidations into rebuilds

      expect(libraryBuilds, greaterThan(libraryBaseline));
      expect(wishlistBuilds, greaterThan(wishlistBaseline));
    });
  });
}
