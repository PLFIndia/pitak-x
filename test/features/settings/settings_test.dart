import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/infrastructure/prefs_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Transitive dependency of shared_preferences, imported only for the
// false-write store seam below (M17). Deliberately NOT added to pubspec so
// the app's dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A settings repo whose writes always fail (persist-failure regression).
class _FailingSettingsRepo implements SettingsRepository {
  static final _boom = StateError('prefs write failed');

  @override
  Future<AppSettings> load() async => AppSettings.defaults;
  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async =>
      right('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
  @override
  Future<Either<Failure, String>> regenerateLibraryId() async =>
      right('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({required bool enabled}) =>
      throw _boom;
  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) => throw _boom;
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) => throw _boom;
  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) => throw _boom;
  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) => throw _boom;
  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({required bool enabled}) =>
      throw _boom;
  @override
  Future<Either<Failure, Unit>> setMaintainerName(String name) => throw _boom;
  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) => throw _boom;
  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) => throw _boom;
}

/// A plugin store whose writes always report `false` — the M17 regression:
/// `SharedPreferences` setters return a success boolean that the repository
/// used to discard, letting the UI confirm writes that never landed.
class _FalseWriteStore extends InMemorySharedPreferencesStore {
  // Super params can't target the named `.withData` constructor, so the
  // explicit initializer stays (lint suppressed with reason).
  // ignore: use_super_parameters
  _FalseWriteStore([Map<String, Object> data = const {}])
    : super.withData(data);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false; // never stores, never succeeds
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrefsSettingsRepository', () {
    test('returns defaults when nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsSettingsRepository(prefs);
      final s = await repo.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.libraryName, '');
      expect(s.maintainerName, '');
      expect(s.librarySort, BookSort.recentlyAdded);
      expect(s.loadRemoteCovers, false); // privacy default: off (#31)
      expect(s.libraryLogo, '');
      expect(s.appLockBiometric, false); // gate opt-in, default off
    });

    test('round-trips each setting', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsSettingsRepository(prefs);

      await repo.setThemeMode(AppThemeMode.dark);
      await repo.setLibraryName('  My Shelf  ');
      await repo.setMaintainerName('Asha');
      await repo.setLibrarySort(BookSort.languageAsc);
      await repo.setLoadRemoteCovers(enabled: true);
      await repo.setLibraryLogo('  covers/abc.jpg  ');
      await repo.setAppLockBiometric(enabled: true);

      final s = await repo.load();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.libraryName, 'My Shelf'); // trimmed
      expect(s.maintainerName, 'Asha');
      expect(s.librarySort, BookSort.languageAsc);
      expect(s.loadRemoteCovers, true);
      expect(s.libraryLogo, 'covers/abc.jpg'); // trimmed
      expect(s.appLockBiometric, true);
    });

    test(
      'getOrCreateLibraryId mints a valid 32-hex id, idempotently',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = PrefsSettingsRepository(prefs);

        final first = (await repo.getOrCreateLibraryId()).getOrElse((_) => '');
        expect(first, hasLength(32));
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(first), isTrue);
        // Idempotent: a second call returns the same stored id.
        expect((await repo.getOrCreateLibraryId()).getOrElse((_) => ''), first);
        // And it is reflected into load().
        expect((await repo.load()).libraryId, first);
      },
    );

    test('setLibraryId adopts a provided id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsSettingsRepository(prefs);

      await repo.setLibraryId('  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  ');
      expect((await repo.load()).libraryId, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      // getOrCreate now returns the adopted id, not a fresh one.
      expect(
        (await repo.getOrCreateLibraryId()).getOrElse((_) => ''),
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
    });

    test(
      'regenerateLibraryId mints a fresh valid id, replacing the old',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = PrefsSettingsRepository(prefs);

        final first = (await repo.getOrCreateLibraryId()).getOrElse((_) => '');
        final regen = (await repo.regenerateLibraryId()).getOrElse((_) => '');
        expect(regen, isNot(first));
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(regen), isTrue);
        expect((await repo.load()).libraryId, regen);
      },
    );

    test('round-trips the split publish-contact fields', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsSettingsRepository(prefs);

      await repo.setPublishContact(
        address: '  14 Banyan Road  ',
        gps: '  12.97, 77.59  ',
        email: '  a@b.com  ',
        phone: '  +91 555  ',
      );

      final s = await repo.load();
      expect(s.publishContactAddress, '14 Banyan Road'); // trimmed
      expect(s.publishContactGps, '12.97, 77.59');
      expect(s.publishContactEmail, 'a@b.com');
      expect(s.publishContactPhone, '+91 555');
    });

    test('migrates a legacy free-text location into Address', () async {
      // Pre-split install: only the old single key is set.
      SharedPreferences.setMockInitialValues({
        'publish_contact_location': 'MG Road, Bengaluru',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = await PrefsSettingsRepository(prefs).load();
      expect(s.publishContactAddress, 'MG Road, Bengaluru');
      expect(s.publishContactGps, ''); // free text never lands in GPS
    });

    test('migrates a legacy coordinate location into GPS', () async {
      SharedPreferences.setMockInitialValues({
        'publish_contact_location': '12.97, 77.59',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = await PrefsSettingsRepository(prefs).load();
      expect(s.publishContactGps, '12.97, 77.59');
      expect(s.publishContactAddress, ''); // a pin never lands in Address
    });

    test('a saved new field wins over the legacy location key', () async {
      // Both old and new keys present (user re-saved post-upgrade): the new
      // value is authoritative; the legacy key is ignored.
      SharedPreferences.setMockInitialValues({
        'publish_contact_location': 'OLD VALUE',
        'publish_contact_address': 'New Address',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = await PrefsSettingsRepository(prefs).load();
      expect(s.publishContactAddress, 'New Address');
    });

    test('an explicitly cleared field does not resurrect legacy', () async {
      // address saved as '' (user cleared it) but legacy still lingers —
      // empty-string is a real stored value and must win over the legacy key.
      SharedPreferences.setMockInitialValues({
        'publish_contact_location': 'OLD VALUE',
        'publish_contact_address': '',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = await PrefsSettingsRepository(prefs).load();
      expect(s.publishContactAddress, '');
    });

    test('tolerates an unknown stored token', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'bogus',
        'library_sort': 'nonsense',
      });
      final prefs = await SharedPreferences.getInstance();
      final s = await PrefsSettingsRepository(prefs).load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.librarySort, BookSort.recentlyAdded);
    });
  });

  group('SettingsController', () {
    test('setThemeMode persists and updates state', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Wait for initial load.
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(AppThemeMode.light);

      expect(
        container.read(settingsControllerProvider).value!.themeMode,
        AppThemeMode.light,
      );
      // Persisted: a fresh repo sees it.
      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getString('theme_mode'), 'light');
    });

    // Regression for REVIEW_FINDINGS_2 (carried Minor): a prefs write
    // failure must fold into AsyncError state — not escape as an unhandled
    // async error from an un-awaited setter — and must not publish a
    // preference the device never stored.
    test(
      'a persist failure becomes AsyncError and keeps the old state',
      () async {
        final container = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWith(
              (ref) async => _FailingSettingsRepo(),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(settingsControllerProvider.future);

        // Must complete normally (no throw) even though the write fails.
        await container
            .read(settingsControllerProvider.notifier)
            .setThemeMode(AppThemeMode.light);

        final s = container.read(settingsControllerProvider);
        expect(s.hasError, isTrue);
        // The failed write was never published as if it had succeeded.
        expect(s.valueOrNull?.themeMode, isNot(AppThemeMode.light));
      },
    );

    test('setMaintainerName trims and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      await container
          .read(settingsControllerProvider.notifier)
          .setMaintainerName('  Khoj  ');

      final s = container.read(settingsControllerProvider).value!;
      expect(s.maintainerName, 'Khoj');
    });

    test('setLibraryLogo + setAppLockBiometric persist and update', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      final notifier = container.read(settingsControllerProvider.notifier);

      await notifier.setLibraryLogo('covers/logo.jpg');
      await notifier.setAppLockBiometric(enabled: true);

      final s = container.read(settingsControllerProvider).value!;
      expect(s.libraryLogo, 'covers/logo.jpg');
      expect(s.appLockBiometric, true);

      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getString('library_logo'), 'covers/logo.jpg');
      expect(prefs.getBool('app_lock_biometric'), true);

      // Clearing the logo resets to blank (default Pitak icon).
      await notifier.setLibraryLogo('');
      expect(container.read(settingsControllerProvider).value!.libraryLogo, '');
    });

    test(
      'getOrCreateLibraryId + setLibraryId + regenerate update state',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(settingsControllerProvider.future);
        final notifier = container.read(settingsControllerProvider.notifier);

        final minted = (await notifier.getOrCreateLibraryId()).getOrElse(
          (_) => '',
        );
        expect(minted, isNotEmpty);
        expect(
          container.read(settingsControllerProvider).value!.libraryId,
          minted,
        );

        await notifier.setLibraryId('cccccccccccccccccccccccccccccccc');
        expect(
          container.read(settingsControllerProvider).value!.libraryId,
          'cccccccccccccccccccccccccccccccc',
        );

        await notifier.regenerateLibraryId();
        final after = container
            .read(settingsControllerProvider)
            .value!
            .libraryId;
        expect(after, isNot('cccccccccccccccccccccccccccccccc'));
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(after), isTrue);
      },
    );
  });

  group('M17 — plugin reports false (write never landed)', () {
    // Installs a store whose setValue always returns false, then hands the
    // repository a SharedPreferences bound to it. Mirrors the plugin contract:
    // setString/setBool surface the store's boolean unchanged.
    Future<PrefsSettingsRepository> falseWriteRepo() async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FalseWriteStore();
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final prefs = await SharedPreferences.getInstance();
      return PrefsSettingsRepository(prefs);
    }

    test(
      'every setter becomes a StorageFailure, never silent success',
      () async {
        final repo = await falseWriteRepo();

        // Minting paths first, on a pristine store: the plugin ALSO caches
        // values in memory when a write fails, so a prior failed setLibraryId
        // would make getOrCreateLibraryId answer from the cache without a
        // write. Fresh store = the mint/persist write actually happens.
        expect((await repo.getOrCreateLibraryId()).isLeft(), isTrue);
        expect((await repo.regenerateLibraryId()).isLeft(), isTrue);

        expect((await repo.setThemeMode(AppThemeMode.light)).isLeft(), isTrue);
        expect((await repo.setLibraryName('x')).isLeft(), isTrue);
        expect((await repo.setMaintainerName('x')).isLeft(), isTrue);
        expect(
          (await repo.setLibrarySort(BookSort.languageAsc)).isLeft(),
          isTrue,
        );
        expect(
          (await repo.setLoadRemoteCovers(enabled: true)).isLeft(),
          isTrue,
        );
        expect(
          (await repo.setPublishContact(
            address: 'a',
            gps: '',
            email: '',
            phone: '',
          )).isLeft(),
          isTrue,
        );
        expect((await repo.setLibraryLogo('covers/x.jpg')).isLeft(), isTrue);
        expect(
          (await repo.setAppLockBiometric(enabled: true)).isLeft(),
          isTrue,
        );
        expect((await repo.setLibraryId('c' * 32)).isLeft(), isTrue);
      },
    );

    test('controller keeps last-known-good state on a false write', () async {
      SharedPreferences.setMockInitialValues({});
      // Seed the READ side (prefixed keys) while every write reports false.
      SharedPreferencesStorePlatform.instance = _FalseWriteStore({
        'flutter.theme_mode': 'light',
      });
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      await container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(AppThemeMode.dark);

      final s = container.read(settingsControllerProvider);
      expect(s.hasError, isTrue);
      expect(s.error, isA<StorageFailure>());
      // The failed write was never published; the old value stays readable.
      expect(s.valueOrNull?.themeMode, AppThemeMode.light);
    });

    test('getOrCreateLibraryId surfaces the failure to the caller', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FalseWriteStore();
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      final minted = await container
          .read(settingsControllerProvider.notifier)
          .getOrCreateLibraryId();
      expect(minted.isLeft(), isTrue);
      // No phantom ID was published into state.
      expect(
        container.read(settingsControllerProvider).valueOrNull?.libraryId,
        '',
      );
    });
  });
}
