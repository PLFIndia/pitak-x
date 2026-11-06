import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/own_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/settings/infrastructure/prefs_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _oldId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _oldFingerprint = 'c' * 64;
final _newFingerprint = 'd' * 64;

final class _FailNextNameWrite extends PrefsSettingsRepository {
  _FailNextNameWrite(super.prefs);

  bool fail = false;

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async {
    if (fail) return left(const StorageFailure('synthetic name failure'));
    return super.setLibraryName(name);
  }
}

void main() {
  test(
    'prefs roundtrip validates stored overrides and explicit clear',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsSettingsRepository(prefs);

      expect(
        (await repo.setPublishedFingerprint(_oldFingerprint)).isRight(),
        isTrue,
      );
      expect((await repo.load()).publishedFingerprint, _oldFingerprint);
      expect((await repo.setPublishedFingerprint('not-hex')).isLeft(), isTrue);
      await prefs.setString('published_fingerprint', 'NOT-HEX');
      expect((await repo.load()).publishedFingerprint, isNull);
      expect((await repo.setPublishedFingerprint(null)).isRight(), isTrue);
      expect((await repo.load()).publishedFingerprint, isNull);
    },
  );

  test(
    'override survives first mint and clears on ID adoption/regeneration',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = PrefsSettingsRepository(prefs);
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      addTearDown(container.dispose);
      final settings = container.read(settingsControllerProvider.notifier);
      await container.read(settingsControllerProvider.future);

      await settings.setPublishedFingerprint(_oldFingerprint);
      await settings.getOrCreateLibraryId();
      expect(
        container.read(settingsControllerProvider).value?.publishedFingerprint,
        _oldFingerprint,
      );
      await settings.setLibraryId(_newId);
      expect(
        container.read(settingsControllerProvider).value?.publishedFingerprint,
        isNull,
      );
      await settings.setPublishedFingerprint(_oldFingerprint);
      await settings.regenerateLibraryId();
      expect(
        container.read(settingsControllerProvider).value?.publishedFingerprint,
        isNull,
      );
    },
  );

  test('ownFingerprintOf prefers a valid override over the derived label', () {
    final derived = LibraryFingerprint.of(_oldId);
    final settings = AppSettings(
      libraryId: _oldId,
      publishedFingerprint: _oldFingerprint,
    );
    expect(ownFingerprintOf(settings), _oldFingerprint);
    expect(
      ownFingerprintOf(settings.copyWith(publishedFingerprint: null)),
      derived,
    );
    expect(
      ownFingerprintOf(settings.copyWith(publishedFingerprint: 'bad')),
      derived,
    );
  });

  test(
    'failed adoption name write restores previous ID and override',
    () async {
      SharedPreferences.setMockInitialValues({
        'library_id': _oldId,
        'library_name': 'Old name',
        'published_fingerprint': _oldFingerprint,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = _FailNextNameWrite(prefs)..fail = true;
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      addTearDown(container.dispose);
      final settings = container.read(settingsControllerProvider.notifier);
      await container.read(settingsControllerProvider.future);

      final adopted = await settings.adopt(
        id: _newId,
        name: 'New name',
        publishedFingerprint: _newFingerprint,
      );

      expect(adopted.outcome, LibraryAdoptionOutcome.notAdopted);
      final memory = container.read(settingsControllerProvider).value!;
      final disk = await repo.load();
      for (final actual in [memory, disk]) {
        expect(actual.libraryId, _oldId);
        expect(actual.libraryName, 'Old name');
        expect(actual.publishedFingerprint, _oldFingerprint);
      }
    },
  );
}
