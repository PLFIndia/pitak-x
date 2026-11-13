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
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_ports.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/infrastructure/prefs_settings_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_document_picker.dart';
import '../library/replacement_test_guard.dart';
import '../periodicals/application/periodical_fakes.dart';
import '../publish/support/availability_lane_fakes.dart';
import '../publish/support/publish_state_fixtures.dart';
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

/// A vault that answers what the test scripted, one answer for each unlock
/// (an empty vault when nothing is scripted), and can park an unlock until
/// the test lets it go: this is how a test holds a restore half-way.
class _ScriptedVault with VaultWriteUnsupported implements VaultRepository {
  /// The answers of the next unlocks, in order.
  final List<Either<Failure, VaultData>> answers = [];

  /// Completed when the first unlock is reached, when set.
  Completer<void>? entered;

  /// The unlock waits for this, when set.
  Completer<void>? gate;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    final reached = entered;
    if (reached != null && !reached.isCompleted) reached.complete();
    await gate?.future;
    return answers.isEmpty ? right(VaultData.empty) : answers.removeAt(0);
  }
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
  Future<Either<Failure, Unit>> setLibrarySort(LibrarySort sort) async =>
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
  Future<Either<Failure, Unit>> setPublishLocationSharing(
    LocationSharing sharing,
  ) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setNetworkMapTilesConsent({
    required bool enabled,
  }) async => right(unit);
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setAutoPublishAvailability({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setLookupIsbnAfterScan({
    required bool enabled,
  }) async => right(unit);
}

void main() {
  late Directory tmp;

  /// Plays the app's picker (BR6): hands out real files as "the private
  /// copy of the chosen backup" and records who gave which copy back.
  late FakeDocumentPicker picker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_ctrl_test');
    picker = FakeDocumentPicker(Directory('${tmp.path}/picked'));
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// The REAL storage chain (M02): docs dir → data generations → active
  /// generation → database / covers / vault store → restorer. Only the Rust
  /// vault is faked. This is what proves the whole app follows a generation
  /// switch, not just the restorer.
  ProviderContainer makeContainer({
    SettingsRepository? settings,
    NetworkRepository? network,
    FakePeriodicals? periodicals,
    MemoryKeysReset? keys,
    VaultRepository? vault,
    List<Override> extra = const [],
  }) {
    // Plan J9: the generation switch runs through the publish feature's
    // keys reset; in memory here (no prefs, no publish records on disk).
    final keysReset = keys ?? MemoryKeysReset();
    final container = ProviderContainer(
      overrides: [
        catalogueKeysResetProvider.overrideWith((ref) async => keysReset.reset),
        appDocsDirProvider.overrideWith((ref) async => tmp),
        // BR6: a restore stages its databases under the temporary folder,
        // and the copy of the backup comes from (and goes back to) the
        // picker.
        appTempDirProvider.overrideWith(
          (ref) async => Directory('${tmp.path}/app_temp'),
        ),
        documentPickerProvider.overrideWith((ref) async => picker),
        vaultRepositoryProvider.overrideWithValue(vault ?? _FakeVault()),
        nowTickProvider.overrideWith((ref) => 0),
        if (periodicals != null)
          periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        if (settings != null)
          settingsRepositoryProvider.overrideWith((ref) async => settings),
        // §5.10 failure-path seam: skip the real Drift repository (and its
        // migration await) when the test needs a failing replaceAll.
        if (network != null)
          networkRepositoryProvider.overrideWith((ref) async => network),
        ...extra,
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
  PickedDocument vaultOnlyArchive() {
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
    return picker.place(ZipEncoder().encode(a));
  }

  test('maps a corrupt archive to AsyncError(BackupCorruptFailure)', () async {
    final container = makeContainer();
    final passphrase = SecretBytes(Uint8List.fromList([1, 2, 3]));

    await container
        .read(restoreControllerProvider.notifier)
        .restore(
          archive: picker.place([0, 1, 2, 3]), // not a zip
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
        .restore(archive: picker.place([0, 1, 2, 3]), passphrase: passphrase);

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
          archive: vaultOnlyArchive(),
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
          archive: picker.place([0, 1, 2, 3]), // not a zip
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
    expect(manifest.manifest.hasBackupBlob, isTrue);
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
    final zip = picker.place(ZipEncoder().encode(a));

    await container
        .read(restoreControllerProvider.notifier)
        .restore(archive: zip); // N13: null passphrase, no crash

    final state = container.read(restoreControllerProvider);
    expect(state.hasValue, isTrue);
    expect(state.value?.booksRestored, 0);
  });

  group('plan J9 — a restore marks the published keys unusable first', () {
    PickedDocument emptyArchive() {
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
      return picker.place(ZipEncoder().encode(a));
    }

    test('flags cleared before the switch, then the lane is told', () async {
      final keys = MemoryKeysReset();
      keys.gitHub.current = const PublishManifest(
        repo: 'me/lib',
        fileShas: {'books.json': 'b1', 'availability.json': 'a1'},
        catalogueKeyed: true,
      );
      final container = makeContainer(keys: keys);
      final before = await container.read(activeDataGenerationProvider.future);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: emptyArchive());

      expect(container.read(restoreControllerProvider).hasValue, isTrue);
      final after = await container.read(activeDataGenerationProvider.future);
      expect(after.name, isNot(before.name), reason: 'the switch happened');
      expect(keys.gitHub.current.catalogueKeyed, isFalse);
      expect(
        keys.gitHub.current.shaFor('availability.json'),
        'a1',
        reason: 'the file stays recorded, so a later publish can delete it',
      );
      expect(keys.idsChanged, 1);
    });

    test('a reset that cannot be saved stops the restore first', () async {
      final keys = MemoryKeysReset();
      keys.gitHub
        ..current = const PublishManifest(
          repo: 'me/lib',
          fileShas: {'books.json': 'b1'},
          catalogueKeyed: true,
        )
        ..saveFails = true;
      final container = makeContainer(keys: keys);
      final before = await container.read(activeDataGenerationProvider.future);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: emptyArchive());

      expect(container.read(restoreControllerProvider).hasError, isTrue);
      final after = await container.read(activeDataGenerationProvider.future);
      expect(after.name, before.name, reason: 'fail closed: nothing switched');
      expect(keys.gitHub.current.catalogueKeyed, isTrue);
      expect(keys.idsChanged, 0);
    });
  });

  group('plan CV7 — the publishing record is offered after the switch', () {
    PickedDocument archiveWith({String? publishState}) {
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 123,
          'hasBooks': false,
          'hasWishlist': false,
          'hasBorrowers': false,
          'hasBackupBlob': false,
          'hasCovers': false,
          if (publishState != null) 'hasPublishState': true,
        }),
      );
      final a = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      if (publishState != null) {
        final bytes = utf8.encode(publishState);
        a.addFile(ArchiveFile('publish_state.json', bytes.length, bytes));
      }
      return picker.place(ZipEncoder().encode(a));
    }

    List<Override> publishOverrides(PublishStateAdopter adopter) => [
      publishStateAdopterProvider.overrideWith((ref) async => adopter),
      // An adopted record invalidates these two; in debug builds that BUILDS
      // them, so they are pinned to plain values here.
      publishedSiteUrlProvider.overrideWith((ref) async => null),
      publishSiteStatusProvider.overrideWith(
        (ref) async => const PublishSiteStatus(
          activeHost: null,
          target: null,
          verifiedSiteUrl: null,
          setupMessage: null,
        ),
      ),
    ];

    test('the archived record reaches the adopter; its outcome is on the '
        'summary', () async {
      final adopter = _RecordingAdopter(PublishStateRestoreOutcome.adopted);
      final container = makeContainer(extra: publishOverrides(adopter))
        ..listen(restoreControllerProvider, (_, _) {});

      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archive: archiveWith(
              publishState: PublishStateBackupCodec.encode(archivedState()),
            ),
          );

      final summary = container.read(restoreControllerProvider).value!;
      expect(adopter.offered.single.coverSalt, archiveSalt);
      expect(summary.publishStateOutcome, PublishStateRestoreOutcome.adopted);
      expect(summary.publishStateInvalid, isFalse);
    });

    test('"kept" is reported as such', () async {
      final adopter = _RecordingAdopter(
        PublishStateRestoreOutcome.keptThisPhone,
      );
      final container = makeContainer(extra: publishOverrides(adopter))
        ..listen(restoreControllerProvider, (_, _) {});
      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archive: archiveWith(
              publishState: PublishStateBackupCodec.encode(archivedState()),
            ),
          );
      expect(
        container.read(restoreControllerProvider).value!.publishStateOutcome,
        PublishStateRestoreOutcome.keptThisPhone,
      );
    });

    test('an adopter that cannot be built is "not applied"; the restore '
        'stands', () async {
      final container = makeContainer(
        extra: [
          publishStateAdopterProvider.overrideWith(
            (ref) async => throw StateError('no adopter'),
          ),
        ],
      )..listen(restoreControllerProvider, (_, _) {});
      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archive: archiveWith(
              publishState: PublishStateBackupCodec.encode(archivedState()),
            ),
          );
      final state = container.read(restoreControllerProvider);
      expect(state.hasValue, isTrue);
      expect(
        state.value!.publishStateOutcome,
        PublishStateRestoreOutcome.notApplied,
      );
    });

    for (final (name, publishState) in [
      ('no record', null),
      ('an unreadable record', '{}'),
    ]) {
      test('$name: the adopter is never asked', () async {
        final adopter = _RecordingAdopter(PublishStateRestoreOutcome.adopted);
        final container = makeContainer(extra: publishOverrides(adopter))
          ..listen(restoreControllerProvider, (_, _) {});
        await container
            .read(restoreControllerProvider.notifier)
            .restore(archive: archiveWith(publishState: publishState));
        final state = container.read(restoreControllerProvider);
        expect(state.hasValue, isTrue);
        expect(state.value!.publishStateOutcome, isNull);
        expect(state.value!.publishStateInvalid, publishState != null);
        expect(adopter.offered, isEmpty);
      });
    }
  });

  group('N04 — dangling library-logo reference after restore (S9 note)', () {
    // Settings are NOT part of a backup, so a restore can leave the logo
    // reference pointing at a cover file the restored set does not have.
    // These archives carry no covers, so the device's set is carried over
    // verbatim — the logo file is present exactly when the test plants it.
    PickedDocument emptyArchive() {
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
      return picker.place(ZipEncoder().encode(a));
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
          .restore(archive: emptyArchive());

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
          .restore(archive: emptyArchive());

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
          .restore(archive: emptyArchive());

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
          documentPickerProvider.overrideWith((ref) async => picker),
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
            archive: vaultOnlyArchive(),
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
            archive: vaultOnlyArchive(),
            passphrase: SecretBytes(Uint8List.fromList([1])),
          );
      final refusedSecret = SecretBytes(Uint8List.fromList([2]));
      var secondDone = false;
      final second = container
          .read(restoreControllerProvider.notifier)
          .restore(archive: vaultOnlyArchive(), passphrase: refusedSecret)
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
          documentPickerProvider.overrideWith((ref) async => picker),
        ],
      );
      addTearDown(container.dispose);
      final passphrase = SecretBytes(Uint8List.fromList([7]));

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: picker.place([0]), passphrase: passphrase);

      final state = container.read(restoreControllerProvider);
      expect(state.error, isA<UnexpectedFailure>());
      expect(() => passphrase.use((b) => b), throwsStateError);
    });

    test('S9: a successful restore invalidates the library, wishlist and '
        'kept-alive Magazines controllers', () async {
      // N04 behaviour, N11 ownership: the refresh used to be the page's job
      // (lost when the page was popped mid-restore); the controller owns it.
      final container = makeContainer(
        settings: _LogoSettingsRepo(),
        periodicals: FakePeriodicals(),
      );
      var libraryBuilds = 0;
      var wishlistBuilds = 0;
      var periodicalBuilds = 0;
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
        )
        ..listen(
          periodicalsControllerProvider,
          (_, __) => periodicalBuilds++,
          fireImmediately: true,
        );
      await container.read(libraryControllerProvider.future);
      await container.read(wishlistControllerProvider.future);
      await container.read(periodicalsControllerProvider.future);
      await container.pump();
      final libraryBaseline = libraryBuilds;
      final wishlistBaseline = wishlistBuilds;
      final periodicalBaseline = periodicalBuilds;

      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archive: vaultOnlyArchive(),
            passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
          );
      expect(container.read(restoreControllerProvider).hasValue, isTrue);
      await container.pump(); // flush the invalidations into rebuilds
      await container.read(periodicalsControllerProvider.future);

      expect(libraryBuilds, greaterThan(libraryBaseline));
      expect(wishlistBuilds, greaterThan(wishlistBaseline));
      expect(periodicalBuilds, greaterThan(periodicalBaseline));
    });
  });

  group('item 11 — the terminal result is retained until a new archive', () {
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
          documentPickerProvider.overrideWith((ref) async => picker),
          settingsRepositoryProvider.overrideWith(
            (ref) async => _LogoSettingsRepo(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a completed restore survives pop, the old auto-dispose point and '
        'reopen', () async {
      // Before: the controller was autoDispose with a per-run keep-alive
      // link, so the summary vanished one event-loop turn after the run
      // finished with no listener — reopening Restore showed IDLE.
      final gate = Completer<void>();
      final container = gatedContainer(gate: gate);

      final sub = container.listen(restoreControllerProvider, (_, __) {});
      final future = container
          .read(restoreControllerProvider.notifier)
          .restore(
            archive: vaultOnlyArchive(),
            passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
          );
      sub.close(); // the page is popped: no listener at all
      await container.pump();
      gate.complete();
      await future;

      // Past the old disposal point: the scheduler's `Future(task)` turn
      // and then some.
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      await pumpEventQueue();

      // Reopen: a fresh listener reads the SAME terminal value.
      final reopened = container.listen(
        restoreControllerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(reopened.close);
      final state = container.read(restoreControllerProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, isNotNull, reason: 'summary must be retained');
      expect(state.value!.borrowersRestored, 0);
    });

    test('a terminal failure is retained the same way', () async {
      final container = makeContainer();
      await container
          .read(restoreControllerProvider.notifier)
          .restore(
            archive: picker.place([0, 1, 2, 3]),
            passphrase: SecretBytes(Uint8List.fromList([1])),
          );
      await pumpEventQueue();
      await container.pump();
      await pumpEventQueue();

      expect(
        container.read(restoreControllerProvider).error,
        isA<BackupCorruptFailure>(),
      );
    });

    test('clearResult returns to idle after a terminal state', () async {
      final container = makeContainer();
      final notifier = container.read(restoreControllerProvider.notifier);
      await notifier.restore(
        archive: picker.place([0, 1, 2, 3]),
        passphrase: SecretBytes(Uint8List.fromList([1])),
      );
      expect(container.read(restoreControllerProvider).hasError, isTrue);

      notifier.clearResult();

      final state = container.read(restoreControllerProvider);
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.value, isNull, reason: 'idle again');
    });

    test('clearResult is refused while a restore runs', () async {
      final gate = Completer<void>();
      final container = gatedContainer(gate: gate);
      final notifier = container.read(restoreControllerProvider.notifier);
      final future = notifier.restore(
        archive: vaultOnlyArchive(),
        passphrase: SecretBytes(Uint8List.fromList([1, 2, 3])),
      );
      expect(container.read(restoreControllerProvider).isLoading, isTrue);

      notifier.clearResult();

      expect(
        container.read(restoreControllerProvider).isLoading,
        isTrue,
        reason: 'a running restore keeps its loading state',
      );
      gate.complete();
      await future;
      expect(container.read(restoreControllerProvider).hasValue, isTrue);
    });

    test('keepAlive changes nothing about duplicate refusal or passphrase '
        'disposal', () async {
      final gate = Completer<void>();
      final container = gatedContainer(gate: gate);
      final notifier = container.read(restoreControllerProvider.notifier);
      final firstSecret = SecretBytes(Uint8List.fromList([1]));
      final first = notifier.restore(
        archive: vaultOnlyArchive(),
        passphrase: firstSecret,
      );
      final refusedSecret = SecretBytes(Uint8List.fromList([2]));
      await notifier.restore(
        archive: vaultOnlyArchive(),
        passphrase: refusedSecret,
      );
      expect(() => refusedSecret.use((b) => b), throwsStateError);

      gate.complete();
      await first;
      expect(() => firstSecret.use((b) => b), throwsStateError);
      expect(container.read(restoreControllerProvider).hasValue, isTrue);
    });
  });

  group('§5.10 — identity + network adoption after the switch', () {
    const archiveId = 'cccccccccccccccccccccccccccccccc';

    /// An archive carrying books + identity.json + network.json (no vault).
    PickedDocument identityNetworkArchive({String identityJson = ''}) {
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 123,
          'hasBooks': false,
          'hasWishlist': false,
          'hasBorrowers': false,
          'hasBackupBlob': false,
          'hasCovers': false,
          'hasIdentity': true,
          'hasNetwork': true,
        }),
      );
      final identity = utf8.encode(
        identityJson.isEmpty
            ? '{"libraryId": "$archiveId", "libraryName": "Meera Road"}'
            : identityJson,
      );
      final network = utf8.encode(
        '{"schemaVersion": 1, "libraries": [{"siteUrl": "https://hub.github.io/x/", "name": "Hub", "id": 9}]}',
      );
      final a = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(ArchiveFile('identity.json', identity.length, identity))
        ..addFile(ArchiveFile('network.json', network.length, network));
      return picker.place(ZipEncoder().encode(a));
    }

    /// Holds the autoDispose restore chain alive for the whole test
    /// (handoff §2: an autoDispose provider read via `.future` with several
    /// awaits can be disposed mid-run, and the teardown dispose then
    /// double-completes it). Pins the controller AND the repository chain
    /// `_applyIdentityAndNetwork` reads through. Listeners die with the
    /// container.
    void pinRestoreController(ProviderContainer container) {
      container
        ..listen(restoreControllerProvider, (_, _) {})
        ..listen(networkRepositoryProvider, (_, _) {})
        ..listen(migrateLegacyBookmarksProvider, (_, _) {})
        // DEBUG builds (tests) run riverpod's `_debugAssertCanDependOn`,
        // which BUILDS the target of a `ref.invalidate` — so the restore's
        // network-window invalidation constructs (and then disposes) the
        // whole window/refresh chain mid-test. Pin them too, or teardown
        // races their auto-dispose.
        ..listen(networkControllerProvider, (_, _) {})
        ..listen(networkRefreshControllerProvider, (_, _) {});
    }

    /// Settles the post-restore invalidation cascade (the controllers rebuild
    /// against the new generation) so teardown never races an in-flight
    /// rebuild with the database close.
    Future<void> settleCascade(ProviderContainer container) async {
      await container.read(libraryControllerProvider.future);
      await container.read(wishlistControllerProvider.future);
      await container.read(vaultSessionControllerProvider.future);
      await container.pump();
    }

    test('adopts the identity and replaces the network rows after the '
        'switch', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer(settings: _LogoSettingsRepo());
      pinRestoreController(container);

      // Pre-seed the CURRENT generation's network table with a stale row —
      // it must be GONE after the restore (replace, not merge), which also
      // proves the write lands on the NEW generation's database.
      final before = await container.read(networkRepositoryProvider.future);
      await before.upsertBySiteUrl(
        const NetworkLibrary(
          siteUrl: 'https://stale.github.io/old/',
          name: 'Stale',
        ),
      );

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: identityNetworkArchive());

      final summary = container.read(restoreControllerProvider).value;
      expect(summary, isNotNull);
      expect(summary!.identityAdopted, isTrue);
      expect(summary.networkApplied, isTrue);
      expect(summary.networkRestored, 1);

      // The identity went through the namespace port (N07): the settings
      // STATE moved with disk.
      final settings = await container.read(settingsControllerProvider.future);
      expect(settings.libraryId, archiveId);
      expect(settings.libraryName, 'Meera Road');

      // The new generation's table holds exactly the archive's rows.
      final repo = await container.read(networkRepositoryProvider.future);
      final rows = await repo.loadAll();
      expect(rows.map((r) => r.siteUrl), ['https://hub.github.io/x/']);

      // And the window controller re-reads them (handoff: verify here).
      final window = await container.read(networkControllerProvider.future);
      expect(window.rows.map((r) => r.name), ['Hub']);
      await settleCascade(container);
    });

    test(
      'a recovered published fingerprint is adopted after the new ID',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final fingerprint = 'f' * 64;
        SharedPreferences.setMockInitialValues({
          'library_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'published_fingerprint': 'd' * 64,
        });
        final prefs = await SharedPreferences.getInstance();
        final container = makeContainer(
          settings: PrefsSettingsRepository(prefs),
        );
        pinRestoreController(container);

        await container
            .read(restoreControllerProvider.notifier)
            .restore(
              archive: identityNetworkArchive(
                identityJson: jsonEncode({
                  'libraryId': archiveId,
                  'libraryName': 'Meera Road',
                  'publishedFingerprint': fingerprint,
                }),
              ),
            );

        final summary = container.read(restoreControllerProvider).value!;
        expect(summary.identityAdopted, isTrue);
        expect(summary.restoredPublishedFingerprint, fingerprint);
        final settings = await container.read(
          settingsControllerProvider.future,
        );
        expect(settings.libraryId, archiveId);
        expect(settings.publishedFingerprint, fingerprint);
        expect(prefs.getString('published_fingerprint'), fingerprint);
        await settleCascade(container);
      },
    );

    test('an identity adopt Left is reported; catalogue + network still '
        'applied', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer(settings: _AdoptFailingSettings());
      pinRestoreController(container);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: identityNetworkArchive());

      final summary = container.read(restoreControllerProvider).value!;
      expect(summary.identityAdopted, isFalse);
      expect(summary.identityInvalid, isFalse); // valid entry, failed write
      expect(summary.networkApplied, isTrue);
      expect(summary.networkRestored, 1); // the other extra still applied
      expect(summary.booksRestored, 0); // catalogue restore succeeded
      await settleCascade(container);
    });

    test('an identity whose name write AND rollback both fail is reported as '
        'partially adopted, with the true settings state', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final settings = _AdoptPartialSettings();
      final container = makeContainer(settings: settings);
      pinRestoreController(container);

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: identityNetworkArchive());

      final summary = container.read(restoreControllerProvider).value!;
      expect(summary.identityAdopted, isFalse);
      expect(summary.identityPartiallyAdopted, isTrue);
      expect(summary.identityInvalid, isFalse);
      // Memory must agree with disk: the archived ID, the previous name —
      // never "unchanged" while the new ID is stored (review finding 4).
      final loaded = await container.read(settingsControllerProvider.future);
      expect(loaded.libraryId, archiveId);
      expect(loaded.libraryName, '');
      expect(settings.settings.libraryId, archiveId);
      await settleCascade(container);
    });

    test(
      'an invalid identity.json leaves the current identity untouched',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        SharedPreferences.setMockInitialValues({});
        final container = makeContainer(settings: _LogoSettingsRepo());
        pinRestoreController(container);

        await container
            .read(restoreControllerProvider.notifier)
            .restore(
              archive: identityNetworkArchive(
                identityJson: '{"libraryId": "NOT-HEX", "libraryName": "X"}',
              ),
            );

        final summary = container.read(restoreControllerProvider).value!;
        expect(summary.identityInvalid, isTrue);
        expect(summary.identityAdopted, isFalse);
        // The settings were never touched by an identity write.
        final settings = await container.read(
          settingsControllerProvider.future,
        );
        expect(settings.libraryId, ''); // _LogoSettingsRepo's initial default
        expect(summary.networkApplied, isTrue);
        expect(summary.networkRestored, 1);
        await settleCascade(container);
      },
    );

    test(
      'a replaceAll Left reports networkRestored 0 and keeps the restore',
      () async {
        final container = makeContainer(
          settings: _LogoSettingsRepo(),
          network: _FailingNetworkRepo(),
        );
        pinRestoreController(container);

        await container
            .read(restoreControllerProvider.notifier)
            .restore(archive: identityNetworkArchive());

        final summary = container.read(restoreControllerProvider).value!;
        expect(summary.networkApplied, isFalse);
        expect(summary.networkRestored, 0);
        expect(summary.restoredNetwork, hasLength(1)); // parsed fine…
        expect(summary.networkInvalid, isFalse); // …just not writable
        expect(summary.identityAdopted, isTrue); // identity unaffected
        await settleCascade(container);
      },
    );
  });

  // BR6: who owns the private copy of the chosen backup, and what a running
  // restore tells the page. Every row of the table in the controller's
  // library doc is looked at on disk, through the fake picker.
  group('BR6 — the picked copy (D25) and the cover count (D27)', () {
    /// An archive without a vault and without rows: restores at once.
    List<int> emptyBackup() {
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
      return ZipEncoder().encode(a);
    }

    /// An archive with a vault: the scripted vault decides how it ends.
    List<int> vaultBackup() => File(vaultOnlyArchive().path).readAsBytesSync();

    /// An archive with two cover pictures and nothing else.
    List<int> coversBackup() {
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 123,
          'hasBooks': false,
          'hasWishlist': false,
          'hasBorrowers': false,
          'hasBackupBlob': false,
          'hasCovers': true,
        }),
      );
      final a = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(ArchiveFile('cover_a.jpg', 3, [1, 2, 3]))
        ..addFile(ArchiveFile('cover_b.jpg', 2, [4, 5]));
      return ZipEncoder().encode(a);
    }

    SecretBytes secret() => SecretBytes(Uint8List.fromList([1, 2, 3]));

    bool onDisk(PickedDocument document) => File(document.path).existsSync();

    test('pickArchive asks for a copy under the archive cap, and nothing '
        'else', () async {
      final container = makeContainer();
      final document = picker.place([1, 2, 3]);
      picker
        ..willAnswer(DocumentPicked(document))
        ..willAnswer(const DocumentPickTooLarge());
      final controller = container.read(restoreControllerProvider.notifier);

      final first = await controller.pickArchive();
      final second = await controller.pickArchive();
      final third = await controller.pickArchive();

      expect(picker.caps, List.filled(3, BackupLimits.current.maxArchiveBytes));
      expect((first as DocumentPicked).document, same(document));
      expect(second, isA<DocumentPickTooLarge>());
      expect(third, isA<DocumentPickCancelled>());
      // A pick does not touch the copy or the restore's state.
      expect(onDisk(document), isTrue);
      expect(picker.discarded, isEmpty);
      expect(container.read(restoreControllerProvider).value, isNull);
    });

    test('a picker that cannot be resolved answers "failed"', () async {
      final container = makeContainer(
        extra: [
          documentPickerProvider.overrideWith(
            (ref) async => throw StateError('no temporary folder'),
          ),
        ],
      );

      final result = await container
          .read(restoreControllerProvider.notifier)
          .pickArchive();

      expect(result, isA<DocumentPickFailed>());
    });

    test('releaseArchive removes a copy no restore is reading, at once, and '
        'may be called twice', () async {
      final container = makeContainer();
      final controller = container.read(restoreControllerProvider.notifier);
      final document = picker.place(emptyBackup());

      await controller.releaseArchive(document);
      expect(onDisk(document), isFalse);
      await controller.releaseArchive(document);

      expect(picker.discarded, [document.path, document.path]);
    });

    test('an inspection leaves the copy with its owner', () async {
      final container = makeContainer();
      final document = picker.place(emptyBackup());

      final inspected = await container
          .read(restoreControllerProvider.notifier)
          .inspectArchive(document);

      expect(inspected.isRight(), isTrue);
      expect(onDisk(document), isTrue);
      expect(picker.discarded, isEmpty);
    });

    test('after a restore that succeeded the copy is gone', () async {
      final container = makeContainer();
      final document = picker.place(emptyBackup());

      await container
          .read(restoreControllerProvider.notifier)
          .restore(archive: document);

      expect(container.read(restoreControllerProvider).value, isNotNull);
      expect(onDisk(document), isFalse);
      expect(picker.discarded, [document.path]);
    });

    test('after a restore that failed the copy stays with the page, '
        'unchanged, and a second try works', () async {
      final vault = _ScriptedVault()
        ..answers.add(left(const WrongPassphraseFailure()));
      final container = makeContainer(vault: vault);
      final controller = container.read(restoreControllerProvider.notifier);
      final bytes = vaultBackup();
      final document = picker.place(bytes);

      await controller.restore(archive: document, passphrase: secret());

      expect(
        container.read(restoreControllerProvider).error,
        isA<WrongPassphraseFailure>(),
      );
      expect(File(document.path).readAsBytesSync(), bytes);
      expect(picker.discarded, isEmpty);

      // The second try, with the same copy: the vault now opens.
      await controller.restore(archive: document, passphrase: secret());

      expect(container.read(restoreControllerProvider).value, isNotNull);
      expect(onDisk(document), isFalse);
    });

    test('a copy released DURING a restore is not removed under it; it goes '
        'when that restore has failed', () async {
      final vault = _ScriptedVault()
        ..entered = Completer<void>()
        ..gate = Completer<void>()
        ..answers.add(left(const WrongPassphraseFailure()));
      final container = makeContainer(vault: vault);
      final controller = container.read(restoreControllerProvider.notifier);
      final document = picker.place(vaultBackup());

      final run = controller.restore(archive: document, passphrase: secret());
      await vault.entered!.future;
      // The page is left in the middle of the restore.
      await controller.releaseArchive(document);

      expect(onDisk(document), isTrue, reason: 'the restore is reading it');
      expect(picker.discarded, isEmpty);

      vault.gate!.complete();
      await run;

      expect(container.read(restoreControllerProvider).hasError, isTrue);
      expect(onDisk(document), isFalse);
      expect(picker.discarded, [document.path]);
    });

    test('a copy released during a restore that then succeeds is removed '
        'once', () async {
      final vault = _ScriptedVault()
        ..entered = Completer<void>()
        ..gate = Completer<void>();
      final container = makeContainer(vault: vault);
      final controller = container.read(restoreControllerProvider.notifier);
      final document = picker.place(vaultBackup());

      final run = controller.restore(archive: document, passphrase: secret());
      await vault.entered!.future;
      await controller.releaseArchive(document);
      vault.gate!.complete();
      await run;

      expect(container.read(restoreControllerProvider).value, isNotNull);
      expect(onDisk(document), isFalse);
      expect(picker.discarded, [document.path]);
    });

    test(
      'a release during one restore does not carry over to the next',
      () async {
        // The first restore fails after its copy was released: that copy
        // goes. A second copy, restored afterwards and failing too, must
        // stay with the page: the earlier release was not about it.
        final vault = _ScriptedVault()
          ..entered = Completer<void>()
          ..gate = Completer<void>()
          ..answers.addAll([
            left(const WrongPassphraseFailure()),
            left(const WrongPassphraseFailure()),
          ]);
        final container = makeContainer(vault: vault);
        final controller = container.read(restoreControllerProvider.notifier);
        final first = picker.place(vaultBackup());
        final second = picker.place(vaultBackup());

        final run = controller.restore(archive: first, passphrase: secret());
        await vault.entered!.future;
        await controller.releaseArchive(first);
        vault.gate!.complete();
        await run;
        await controller.restore(archive: second, passphrase: secret());

        expect(onDisk(first), isFalse);
        expect(onDisk(second), isTrue);
      },
    );

    test('releasing ANOTHER copy while a restore runs removes that one at '
        'once', () async {
      final vault = _ScriptedVault()
        ..entered = Completer<void>()
        ..gate = Completer<void>();
      final container = makeContainer(vault: vault);
      final controller = container.read(restoreControllerProvider.notifier);
      final inUse = picker.place(vaultBackup());
      final other = picker.place(emptyBackup());

      final run = controller.restore(archive: inUse, passphrase: secret());
      await vault.entered!.future;
      await controller.releaseArchive(other);

      expect(onDisk(other), isFalse);
      expect(onDisk(inUse), isTrue);

      vault.gate!.complete();
      await run;
    });

    test('a restore that is refused because one runs already leaves its '
        'copy untouched', () async {
      final vault = _ScriptedVault()
        ..entered = Completer<void>()
        ..gate = Completer<void>();
      final container = makeContainer(vault: vault);
      final controller = container.read(restoreControllerProvider.notifier);
      final running = picker.place(vaultBackup());
      final refused = picker.place(emptyBackup());

      final run = controller.restore(archive: running, passphrase: secret());
      await vault.entered!.future;
      await controller.restore(archive: refused);

      expect(onDisk(refused), isTrue);
      expect(picker.discarded, isEmpty);
      // And the copy that is in use is still the first one: releasing the
      // refused one removes it at once.
      await controller.releaseArchive(refused);
      expect(onDisk(refused), isFalse);
      expect(onDisk(running), isTrue);

      vault.gate!.complete();
      await run;
      expect(onDisk(running), isFalse);
    });

    test('a copy the system took away gives the "choose it again" sentence, '
        'and nothing on the device changes', () async {
      final container = makeContainer();
      final controller = container.read(restoreControllerProvider.notifier);
      final document = picker.place(emptyBackup());
      File(document.path).deleteSync();

      await controller.restore(archive: document);

      final error = container.read(restoreControllerProvider).error;
      expect(error, isA<ValidationFailure>());
      expect(
        (error! as ValidationFailure).message,
        'The backup file could not be read. Please choose it again.',
      );
    });

    group('the cover count', () {
      test('is shown while covers are written and gone when the restore '
          'ends', () async {
        final container = makeContainer();
        final seen = <BackupProgress?>[];
        container.listen(restoreProgressProvider, (_, next) => seen.add(next));

        await container
            .read(restoreControllerProvider.notifier)
            .restore(archive: picker.place(coversBackup()));

        expect(container.read(restoreControllerProvider).value, isNotNull);
        final counts = [
          for (final progress in seen)
            if (progress != null) (progress.coversDone, progress.coversTotal),
        ];
        expect(counts, isNotEmpty);
        expect(counts.last, (2, 2));
        expect(seen.last, isNull, reason: 'cleared when the restore ended');
        expect(container.read(restoreProgressProvider), isNull);
      });

      test('a count left from an earlier restore is cleared when the next '
          'one starts, and stays cleared after a failure', () async {
        final vault = _ScriptedVault()
          ..entered = Completer<void>()
          ..gate = Completer<void>()
          ..answers.add(left(const WrongPassphraseFailure()));
        final container = makeContainer(vault: vault);
        final stale = BackupProgress.tryCreate(coversDone: 1, coversTotal: 9);
        container.read(restoreProgressProvider.notifier).show(stale);

        final run = container
            .read(restoreControllerProvider.notifier)
            .restore(
              archive: picker.place(vaultBackup()),
              passphrase: secret(),
            );
        await vault.entered!.future;

        // The restore is parked half-way: the old count is gone already.
        expect(container.read(restoreProgressProvider), isNull);

        vault.gate!.complete();
        await run;

        expect(container.read(restoreControllerProvider).hasError, isTrue);
        expect(container.read(restoreProgressProvider), isNull);
      });

      test('is cleared after an unexpected throw too', () async {
        final container = makeContainer(
          extra: [
            restoreBackupProvider.overrideWith(
              (ref) async => throw StateError('plugin exploded'),
            ),
          ],
        );
        final stale = BackupProgress.tryCreate(coversDone: 1, coversTotal: 9);
        container.read(restoreProgressProvider.notifier).show(stale);

        await container
            .read(restoreControllerProvider.notifier)
            .restore(archive: picker.place(emptyBackup()));

        expect(
          container.read(restoreControllerProvider).error,
          isA<UnexpectedFailure>(),
        );
        expect(container.read(restoreProgressProvider), isNull);
      });
    });
  });
}

/// Settings fake whose ID write always fails — the adopt() Left path.
class _AdoptFailingSettings extends _LogoSettingsRepo {
  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async =>
      left(const StorageFailure('prefs read-only'));
}

/// The archived ID lands, its name write fails, and the rollback of the ID
/// fails too (review finding 4).
class _AdoptPartialSettings extends _LogoSettingsRepo {
  int idWrites = 0;

  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) async {
    idWrites++;
    if (idWrites == 1) {
      settings = settings.copyWith(libraryId: id);
      return right(unit);
    }
    return left(const StorageFailure('prefs read-only'));
  }

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async =>
      left(const StorageFailure('prefs read-only'));
}

/// Network repo whose replaceAll fails (the controller must contain it).
class _FailingNetworkRepo implements NetworkRepository {
  @override
  Future<Either<Failure, Unit>> replaceAll(List<NetworkLibrary> rows) async =>
      left(const StorageFailure('disk full'));

  @override
  Future<List<NetworkLibrary>> loadAll() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the restore offered and answers a fixed outcome.
final class _RecordingAdopter implements PublishStateAdopter {
  _RecordingAdopter(this.outcome);
  final PublishStateRestoreOutcome outcome;
  final List<PublishStateBackup> offered = [];

  @override
  Future<PublishStateRestoreOutcome> adoptRestored(
    PublishStateBackup archived,
  ) async {
    offered.add(archived);
    return outcome;
  }
}
