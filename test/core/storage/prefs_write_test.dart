import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Transitive dependency of shared_preferences, imported only for the
// failure-injection seam below. Deliberately NOT added to pubspec so the
// app's dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A plugin store whose writes fail in a chosen way (fix-plan L9).
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore({
    Map<String, Object> data = const {},
    this.failSet = true,
    this.throwSet = false,
    this.failRemove = false,
  }) : super.withData(data);

  final bool failSet;
  final bool throwSet;
  final bool failRemove;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwSet) {
      throw PlatformException(code: 'write_failed', message: 'disk full');
    }
    // A failing store never persists; the plugin cache still changed.
    return !failSet;
  }

  @override
  Future<bool> remove(String key) async {
    if (failRemove) return false;
    return super.remove(key);
  }
}

Future<SharedPreferences> installStore(_FailingStore store) async {
  // Reset the plugin singleton/cache first, then install the failing store so
  // `getInstance` loads the seeded data through it.
  SharedPreferences.setMockInitialValues({});
  SharedPreferencesStorePlatform.instance = store;
  addTearDown(() => SharedPreferences.setMockInitialValues({}));
  return SharedPreferences.getInstance();
}

void main() {
  test('a successful write is stored and reported', () async {
    final prefs = await installStore(_FailingStore(failSet: false));

    final saved = await writePrefsString(prefs, 'k', 'v', what: 'test');

    expect(saved.isRight(), isTrue);
    expect(prefs.getString('k'), 'v');
  });

  test('a false result restores the previous cached value', () async {
    // The regression (L9): the plugin updates its cache before the platform
    // write, so without repair this read would return the NEW value.
    final prefs = await installStore(_FailingStore(data: {'flutter.k': 'old'}));

    final saved = await writePrefsString(prefs, 'k', 'new', what: 'test');

    expect(saved.isLeft(), isTrue);
    expect(prefs.getString('k'), 'old');
  });

  test('a thrown plugin error restores the previous cached value', () async {
    final prefs = await installStore(
      _FailingStore(data: {'flutter.k': 'old'}, throwSet: true),
    );

    final saved = await writePrefsString(prefs, 'k', 'new', what: 'test');

    expect(saved.isLeft(), isTrue);
    expect(prefs.getString('k'), 'old');
  });

  test('a failed first write leaves the key absent, not phantom', () async {
    final prefs = await installStore(_FailingStore());

    final saved = await writePrefsString(prefs, 'k', 'new', what: 'test');

    expect(saved.isLeft(), isTrue);
    expect(prefs.getString('k'), isNull);
  });

  test('the bool helper has the same contract', () async {
    final prefs = await installStore(
      _FailingStore(data: {'flutter.flag': true}),
    );

    final saved = await writePrefsBool(prefs, 'flag', false, what: 'test');

    expect(saved.isLeft(), isTrue);
    expect(prefs.getBool('flag'), isTrue);
  });

  test('a failed remove restores the value the cache still holds', () async {
    final prefs = await installStore(
      _FailingStore(data: {'flutter.k': 'old'}, failRemove: true),
    );

    final removed = await removePrefs(prefs, 'k', what: 'test');

    expect(removed.isLeft(), isTrue);
    expect(prefs.getString('k'), 'old');
  });

  test('a successful remove deletes the value', () async {
    final prefs = await installStore(
      _FailingStore(data: {'flutter.k': 'old'}, failRemove: false),
    );

    final removed = await removePrefs(prefs, 'k', what: 'test');

    expect(removed.isRight(), isTrue);
    expect(prefs.getString('k'), isNull);
  });

  test('a restore that also fails still reports the failure', () async {
    // Even when the second platform call fails, the in-memory cache was
    // restored by the attempt, and the caller must never see success.
    final prefs = await installStore(
      _FailingStore(
        data: {'flutter.k': 'old'},
        failSet: true,
        failRemove: true,
      ),
    );

    final saved = await writePrefsString(prefs, 'k', 'new', what: 'test');

    expect(saved.isLeft(), isTrue);
    expect(prefs.getString('k'), 'old');
  });
}
