import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cloudflare_credential_store.dart';

import '../support/cloudflare_fakes.dart';

final class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

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
    if (failWrite) throw Exception('private platform detail');
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
  }) async {
    if (failRead) throw Exception('private platform detail');
    return values[key];
  }

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
    if (failDelete) throw Exception('private platform detail');
    values.remove(key);
  }
}

T _right<T>(Either<Failure, T> result) => switch (result) {
  Right(value: final value) => value,
  Left(value: final failure) => fail('Expected right, got $failure'),
};

void main() {
  test('round-trips one full record and derives the sealed target', () async {
    final storage = _FakeStorage();
    final store = SecureStorageCloudflareCredentialStore(storage: storage);
    final connection =
        CloudflareConnection.verifiedToken(
              cloudflareTestToken(),
              tokenExpiresOn: DateTime.utc(2027, 1, 2, 3, 4, 5),
            )
            .selectAccount(id: cloudflareTestAccount(), name: 'Library account')
            .selectSubdomain(cloudflareTestSubdomain(), confirmed: true)
            .selectWorker(cloudflareTestWorker())
            .markVerificationReadBack();

    expect((await store.save(connection)).isRight(), isTrue);
    expect(storage.values.keys, {SecureStorageCloudflareCredentialStore.key});
    final read = _right(await store.read())!;

    expect(read.status.accountId?.value, cloudflareTestAccountId);
    expect(
      read.status.target?.siteUrl,
      'https://pitak-library.library.workers.dev/',
    );
    expect(read.status.workersWriteConfirmed, isTrue);
    expect(read.verifiedWorkerName?.value, 'pitak-library');
    expect(
      read.selectWorker(cloudflareTestWorker('other')).status.target,
      isNull,
    );
    expect(read.tokenExpiresOn, DateTime.utc(2027, 1, 2, 3, 4, 5));
    expect(read.toString(), 'CloudflareConnection(***)');
  });

  test(
    'a fresh token replaces the whole record and cannot inherit a target',
    () async {
      final storage = _FakeStorage();
      final store = SecureStorageCloudflareCredentialStore(storage: storage);
      await store.save(cloudflareTestConnection(writeConfirmed: true));

      await store.save(
        CloudflareConnection.verifiedToken(cloudflareTestToken(account: true)),
      );
      final read = _right(await store.read())!;

      expect(read.status.hasToken, isTrue);
      expect(read.status.accountId, isNull);
      expect(read.status.target, isNull);
      expect(read.status.workersWriteConfirmed, isFalse);
    },
  );

  test('token-only partial setup round-trips', () async {
    final store = SecureStorageCloudflareCredentialStore(
      storage: _FakeStorage(),
    );
    await store.save(CloudflareConnection.verifiedToken(cloudflareTestToken()));
    final read = _right(await store.read())!;
    expect(read.status.hasToken, isTrue);
    expect(read.status.accountId, isNull);
    expect(read.status.target, isNull);
  });

  test(
    'corrupt JSON and unknown schemas fail closed, not signed out',
    () async {
      final storage = _FakeStorage();
      final store = SecureStorageCloudflareCredentialStore(storage: storage);
      storage.values[SecureStorageCloudflareCredentialStore.key] = '{bad';
      expect((await store.read()).isLeft(), isTrue);

      storage.values[SecureStorageCloudflareCredentialStore.key] = jsonEncode({
        'schema': 999,
      });
      expect((await store.read()).isLeft(), isTrue);
    },
  );

  test('an inconsistent confirmed record is refused', () async {
    final storage = _FakeStorage();
    final store = SecureStorageCloudflareCredentialStore(storage: storage);
    storage.values[SecureStorageCloudflareCredentialStore.key] = jsonEncode({
      'schema': 1,
      'token': cloudflareTestToken().use((value) => value),
      'addressConfirmed': true,
      'workersWriteConfirmed': false,
    });
    expect((await store.read()).isLeft(), isTrue);
  });

  test('a stored URL cannot override the derived target identity', () async {
    final storage = _FakeStorage();
    final store = SecureStorageCloudflareCredentialStore(storage: storage);
    await store.save(cloudflareTestConnection());
    const key = SecureStorageCloudflareCredentialStore.key;
    final decoded = jsonDecode(storage.values[key]!) as Map<String, dynamic>;
    decoded['siteUrl'] = 'https://evil.example/';
    decoded['targetId'] = 'cloudflare:evil';
    storage.values[key] = jsonEncode(decoded);

    final read = _right(await store.read())!;
    expect(
      read.status.target?.siteUrl,
      'https://pitak-library.library.workers.dev/',
    );
    expect(read.status.target?.targetId, isNot('cloudflare:evil'));
  });

  test('read, write, and clear failures are typed and redacted', () async {
    final storage = _FakeStorage();
    final store = SecureStorageCloudflareCredentialStore(storage: storage);
    storage.failRead = true;
    final read = await store.read();
    expect(read.isLeft(), isTrue);
    expect(read.fold((l) => l, (_) => null), isA<StorageFailure>());
    expect(read.toString(), isNot(contains('private platform detail')));

    storage
      ..failRead = false
      ..failWrite = true;
    final write = await store.save(cloudflareTestConnection());
    expect(write.isLeft(), isTrue);
    expect(write.toString(), isNot(contains('private platform detail')));

    storage
      ..failWrite = false
      ..failDelete = true;
    final clear = await store.clear();
    expect(clear.isLeft(), isTrue);
    expect(clear.toString(), isNot(contains('private platform detail')));
  });

  test(
    'clear deletes only cf_connection and preserves unrelated public keys',
    () async {
      final storage = _FakeStorage()
        ..values['publish_host_state'] = 'public-journal';
      final store = SecureStorageCloudflareCredentialStore(storage: storage);
      await store.save(cloudflareTestConnection());

      expect((await store.clear()).isRight(), isTrue);
      expect(storage.values, {'publish_host_state': 'public-journal'});
      expect(_right(await store.read()), isNull);
    },
  );

  test('clear works on an unreadable value from a newer schema', () async {
    // A newer app version wrote a record this build cannot decode. Forgetting
    // it must work without decoding: only the key is deleted.
    final storage = _FakeStorage()
      ..values[SecureStorageCloudflareCredentialStore.key] = jsonEncode({
        'schema': 99,
        'token': 'unreadable-to-this-build',
      });
    final store = SecureStorageCloudflareCredentialStore(storage: storage);

    expect((await store.read()).isLeft(), isTrue);
    expect((await store.clear()).isRight(), isTrue);
    expect(storage.values, isEmpty);
  });

  test('clear works on an undecodable value', () async {
    final storage = _FakeStorage()
      ..values[SecureStorageCloudflareCredentialStore.key] = '{not json';
    final store = SecureStorageCloudflareCredentialStore(storage: storage);

    expect((await store.read()).isLeft(), isTrue);
    expect((await store.clear()).isRight(), isTrue);
    expect(storage.values, isEmpty);
  });

  test(
    'token kind routes account and legacy shapes without inspecting prefixes',
    () {
      expect(cloudflareTestToken().kind, CloudflareApiTokenKind.user);
      expect(
        cloudflareTestToken(account: true).kind,
        CloudflareApiTokenKind.account,
      );
      // L1/D7: the unprefixed shape can be either old ownership kind, so it
      // has its own route (user first, account after a 401/403).
      expect(cloudflareLegacyTestToken().kind, CloudflareApiTokenKind.legacy);
    },
  );
}
