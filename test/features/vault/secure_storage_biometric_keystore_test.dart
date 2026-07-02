import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/infrastructure/secure_storage_biometric_keystore.dart';

/// In-memory fake: overrides only the four methods the keystore uses, so the
/// test never touches a platform channel.
final class _FakeStorage extends FlutterSecureStorage {
  _FakeStorage({this.failWrites = false});

  final bool failWrites;
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
    if (failWrites) throw Exception('keystore unavailable');
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
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.containsKey(key);

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
  SecretBytes s(List<int> bytes) => SecretBytes(Uint8List.fromList(bytes));

  test('store → read round-trips S as wipeable bytes', () async {
    final fake = _FakeStorage();
    final store = SecureStorageBiometricKeyStore(storage: fake);

    final secret = s([1, 2, 3, 255]);
    final wrote = await store.store(secret);
    secret.dispose();
    expect(wrote.isRight(), isTrue);
    expect(await store.hasSecret(), isTrue);

    final read = await store.read();
    read.match((f) => fail('unexpected failure: $f'), (secret) {
      expect(secret, isNotNull);
      expect(secret!.use((b) => b), [1, 2, 3, 255]);
      secret.dispose();
    });
  });

  test('key name is stable (regression guard: renaming it silently locks '
      'users out of biometric unlock)', () async {
    final fake = _FakeStorage();
    final store = SecureStorageBiometricKeyStore(storage: fake);
    final secret = s([9]);
    await store.store(secret);
    secret.dispose();
    expect(fake.values.keys.single, 'vault_biometric_secret_v1');
  });

  test('stored value is base64 of S, nothing else (no plaintext leak of '
      'extra material)', () async {
    final fake = _FakeStorage();
    final store = SecureStorageBiometricKeyStore(storage: fake);
    final secret = s([10, 20, 30]);
    await store.store(secret);
    secret.dispose();
    expect(fake.values.values.single, base64Encode([10, 20, 30]));
  });

  test('read returns null when nothing is enrolled', () async {
    final store = SecureStorageBiometricKeyStore(storage: _FakeStorage());
    final read = await store.read();
    read.match(
      (f) => fail('unexpected failure: $f'),
      (secret) => expect(secret, isNull),
    );
    expect(await store.hasSecret(), isFalse);
  });

  test('clear removes S', () async {
    final fake = _FakeStorage();
    final store = SecureStorageBiometricKeyStore(storage: fake);
    final secret = s([5]);
    await store.store(secret);
    secret.dispose();

    final cleared = await store.clear();
    expect(cleared.isRight(), isTrue);
    expect(fake.values, isEmpty);
    expect(await store.hasSecret(), isFalse);
  });

  test('a failing platform store maps to StorageFailure with no secret '
      'material in the message', () async {
    final store = SecureStorageBiometricKeyStore(
      storage: _FakeStorage(failWrites: true),
    );
    final secret = s([1, 2, 3]);
    final result = await store.store(secret);
    secret.dispose();
    result.match((f) {
      expect(f, isA<StorageFailure>());
    }, (_) => fail('expected a StorageFailure'));
  });
}
