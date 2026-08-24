import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/lookup/infrastructure/secure_storage_lookup_key_store.dart';

/// In-memory fake covering only the methods the store uses (same pattern as
/// the vault keystore test) — no platform channels touched.
final class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  test('round-trips a key', () async {
    final store = SecureStorageLookupKeyStore(storage: _FakeStorage());
    expect(await store.googleBooksApiKey(), isNull);
    await store.setGoogleBooksApiKey('AIzaSyB-test-key-1234');
    expect(await store.googleBooksApiKey(), 'AIzaSyB-test-key-1234');
  });

  test('clear removes the key', () async {
    final store = SecureStorageLookupKeyStore(storage: _FakeStorage());
    await store.setGoogleBooksApiKey('AIzaSyB-test-key-1234');
    await store.clearGoogleBooksApiKey();
    expect(await store.googleBooksApiKey(), isNull);
  });

  test('an empty stored value reads as null (no key)', () async {
    final fake = _FakeStorage()..values['google_books_api_key'] = '';
    final store = SecureStorageLookupKeyStore(storage: fake);
    expect(await store.googleBooksApiKey(), isNull);
  });
}
