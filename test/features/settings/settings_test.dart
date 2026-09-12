import 'dart:async';

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

/// A settings repo whose writes finish only when the TEST says so (M16).
///
/// Each write parks on a [Completer] keyed by a label; the test releases them
/// in whatever order it wants. This is the only way to make two setters be
/// "in flight" at the same moment deterministically — a real prefs store
/// answers too fast to overlap on purpose.
class _GatedSettingsRepo implements SettingsRepository {
  final gates = <String, Completer<Either<Failure, Unit>>>{};

  /// Number of writes that have been *started* (reached the repository).
  int started = 0;

  /// Lets the write labelled [name] finish with [result] (default: success).
  /// Releasing a write that has not started yet pre-arms it, so it completes
  /// the instant the controller reaches the repository — the test then only
  /// dictates *which writes are fast*, not the exact interleaving.
  void release(String name, {Either<Failure, Unit>? result}) {
    _gateFor(name).complete(result ?? right(unit));
  }

  Completer<Either<Failure, Unit>> _gateFor(String name) =>
      gates[name] ??= Completer<Either<Failure, Unit>>();

  Future<Either<Failure, Unit>> _gate(String name) {
    started++;
    return _gateFor(name).future;
  }

  @override
  Future<AppSettings> load() async => AppSettings.defaults;
  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async {
    final r = await _gate('libraryId');
    return r.map((_) => 'a' * 32);
  }

  @override
  Future<Either<Failure, String>> regenerateLibraryId() async {
    final r = await _gate('regenerate');
    return r.map((_) => 'b' * 32);
  }

  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({required bool enabled}) =>
      _gate('appLock');
  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) => _gate('setId');
  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) =>
      _gate('logo');
  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) => _gate('name');
  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) => _gate('sort');
  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({required bool enabled}) =>
      _gate('covers');
  @override
  Future<Either<Failure, Unit>> setMaintainerName(String name) =>
      _gate('maintainer');
  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) => _gate('contact');
  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) =>
      _gate('theme');
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

  // M16 (astra-review.md): each setter used to capture a snapshot of ALL
  // settings before awaiting its write and then publish that whole snapshot
  // afterwards. Two overlapping setters captured the same "before"; whichever
  // write finished LAST silently reverted the other's field in memory (disk
  // stayed right — one prefs key per setter). The reviewer's instance: a slow
  // theme write publishing `appLockBiometric: false` after the lock was
  // enabled, so the runtime gate (which reads memory) stayed open.
  group('M16 — overlapping settings mutations', () {
    late _GatedSettingsRepo repo;
    late ProviderContainer container;
    late SettingsController controller;

    setUp(() async {
      repo = _GatedSettingsRepo();
      container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      controller = container.read(settingsControllerProvider.notifier);
    });

    AppSettings current() =>
        container.read(settingsControllerProvider).requireValue;

    test(
      'a slow theme write cannot revert an app-lock enable that landed first',
      () async {
        // Theme is requested first but its write is SLOW; app-lock is
        // requested second and its write is instant. On the old code both
        // started at once with the same snapshot, the lock landed first, and
        // the theme then published `appLockBiometric: false` over it.
        repo.release('appLock');
        final theme = controller.setThemeMode(AppThemeMode.light);
        final lock = controller.setAppLockBiometric(enabled: true);
        await pumpEventQueue();

        repo.release('theme');
        await Future.wait([theme, lock]);

        final s = current();
        expect(s.themeMode, AppThemeMode.light);
        expect(
          s.appLockBiometric,
          isTrue,
          reason: 'the later theme write must not publish a stale lock=false',
        );
      },
    );

    test(
      'minting a library ID in parallel with a name change keeps both',
      () async {
        // Slow name write, instant ID mint. On the old code the ID landed
        // first and the name write then published ITS stale snapshot
        // (libraryId still '') — the clobber, for a path that did not even
        // go through `_update`.
        repo.release('libraryId');
        final name = controller.setLibraryName('Shelf');
        final id = controller.getOrCreateLibraryId();
        await pumpEventQueue();

        repo.release('name');
        await Future.wait([name, id]);

        final s = current();
        expect(s.libraryName, 'Shelf');
        expect(s.libraryId, 'a' * 32);
      },
    );

    test(
      'a failed write in the queue neither blocks nor reverts a later write',
      () async {
        final sort = controller.setLibrarySort(BookSort.languageAsc);
        final covers = controller.setLoadRemoteCovers(enabled: true);
        await pumpEventQueue();

        repo.release('sort', result: left(const StorageFailure('gated')));
        await pumpEventQueue();
        // The queue must have let the second write start.
        expect(repo.gates.containsKey('covers'), isTrue);
        repo.release('covers');
        await Future.wait([sort, covers]);

        final s = container.read(settingsControllerProvider);
        // Last successful publish wins the visible state; the failed field
        // was never applied (fail closed, M17).
        expect(s.valueOrNull?.loadRemoteCovers, isTrue);
        expect(s.valueOrNull?.librarySort, BookSort.recentlyAdded);
      },
    );

    // N07: the merge use case adopts an incoming library ID + name THROUGH
    // this controller (the `LibraryNamespace` port) so the in-memory settings
    // follow the disk. Both writes must sit in ONE queued turn.
    group('LibraryNamespace.adopt (N07)', () {
      test('adopts id + name in one turn; a slow theme write in flight cannot '
          'revert either', () async {
        repo
          ..release('setId')
          ..release('name');
        final theme = controller.setThemeMode(AppThemeMode.dark);
        final adopt = controller.adopt(id: 'b' * 32, name: 'Riverside');
        await pumpEventQueue();

        // The adopt is queued behind the slow theme write — not published yet.
        expect(current().libraryId, '');
        repo.release('theme');
        final adopted = await adopt;
        await theme;

        expect(adopted.isRight(), isTrue);
        final s = current();
        expect(s.themeMode, AppThemeMode.dark);
        expect(s.libraryId, 'b' * 32);
        expect(s.libraryName, 'Riverside');
      });

      test('a failed id write returns left and publishes nothing', () async {
        repo.release(
          'setId',
          result: left(const StorageFailure('prefs write failed')),
        );
        final adopted = await controller.adopt(id: 'b' * 32, name: 'Riverside');

        expect(adopted.getLeft().toNullable(), isA<StorageFailure>());
        expect(current().libraryId, '');
        expect(current().libraryName, '');
        expect(repo.gates.containsKey('name'), isFalse, reason: 'name skipped');
      });

      test('a failed name write (after the id landed) returns left and '
          'publishes neither', () async {
        repo
          ..release('setId')
          ..release(
            'name',
            result: left(const StorageFailure('prefs write failed')),
          );
        final adopted = await controller.adopt(id: 'b' * 32, name: 'Riverside');

        expect(adopted.isLeft(), isTrue);
        // Disk may already hold the ID; memory stays on the last good state
        // (the merge reports the adoption as failed, the next Join retries).
        expect(current().libraryId, '');
        expect(current().libraryName, '');
      });

      test(
        'a blank name adopts only the id and keeps the current name',
        () async {
          repo.release('setId');
          final adopted = await controller.adopt(id: 'b' * 32, name: '   ');

          expect(adopted.isRight(), isTrue);
          expect(current().libraryId, 'b' * 32);
          expect(repo.gates.containsKey('name'), isFalse);
        },
      );

      test('current() returns the minted id and the loaded name', () async {
        repo.release('libraryId');
        final identity = await controller.current();

        final value = identity.getOrElse((f) => fail('current failed: $f'));
        expect(value.id, 'a' * 32);
        expect(value.name, '');
        expect(current().libraryId, 'a' * 32, reason: 'reflected into state');
      });

      test('a THROWING write is a typed left; current() still answers when '
          'an earlier setter left the state in error', () async {
        // `_FailingSettingsRepo` throws from every setter (not a left).
        final failing = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWith(
              (ref) async => _FailingSettingsRepo(),
            ),
          ],
        );
        addTearDown(failing.dispose);
        await failing.read(settingsControllerProvider.future);
        final c = failing.read(settingsControllerProvider.notifier);

        final adopted = await c.adopt(id: 'b' * 32, name: 'Riverside');
        expect(adopted.getLeft().toNullable(), isA<StorageFailure>());
        expect(
          failing.read(settingsControllerProvider).requireValue.libraryId,
          '',
          reason: 'nothing published on a thrown write',
        );

        // Mint the ID first (so the mint inside `current()` has nothing new
        // to publish), then put the state into AsyncError via a plain setter
        // (M17 fold). `current()` must still answer: `future` rejects, so the
        // name comes from the cached last-good state.
        expect((await c.getOrCreateLibraryId()).isRight(), isTrue);
        await c.setThemeMode(AppThemeMode.light);
        expect(failing.read(settingsControllerProvider).hasError, isTrue);
        final identity = await c.current();
        final value = identity.getOrElse((f) => fail('current failed: $f'));
        expect(value.id, 'a' * 32);
        expect(value.name, '');
        expect(
          failing.read(settingsControllerProvider).hasError,
          isTrue,
          reason: 'reading the identity must not mask the failed write',
        );
      });

      test(
        'current() is left when the mint fails (no phantom id, M17)',
        () async {
          repo.release(
            'libraryId',
            result: left(const StorageFailure('prefs write failed')),
          );
          final identity = await controller.current();

          expect(identity.isLeft(), isTrue);
          expect(current().libraryId, '');
        },
      );
    });
  });
}
