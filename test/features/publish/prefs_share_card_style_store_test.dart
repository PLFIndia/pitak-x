import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_share_card_style_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Transitive dependency of shared_preferences, imported only for the
// false-write store seam below (M17, same as settings_test.dart).
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A plugin store whose writes always report `false` (M17 regression shape).
class _FalseWriteStore extends InMemorySharedPreferencesStore {
  _FalseWriteStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrefsShareCardStyleStore', () {
    test('defaults to classic when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsShareCardStyleStore(
        await SharedPreferences.getInstance(),
      );
      expect(await store.load(), ShareCardStyle.classic);
    });

    test('round-trips every style', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsShareCardStyleStore(
        await SharedPreferences.getInstance(),
      );
      for (final style in ShareCardStyle.values) {
        final saved = await store.save(style);
        expect(saved.isRight(), isTrue);
        expect(await store.load(), style);
      }
    });

    test('a corrupt stored token falls back to classic', () async {
      SharedPreferences.setMockInitialValues({
        PrefsShareCardStyleStore.key: 'not-a-style',
      });
      final store = PrefsShareCardStyleStore(
        await SharedPreferences.getInstance(),
      );
      expect(await store.load(), ShareCardStyle.classic);
    });

    test('a write the plugin rejects is a StorageFailure (M17)', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FalseWriteStore();
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final store = PrefsShareCardStyleStore(
        await SharedPreferences.getInstance(),
      );
      final result = await store.save(ShareCardStyle.dark);
      expect(result.isLeft(), isTrue);
      result.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected a failure'),
      );
    });
  });
}
