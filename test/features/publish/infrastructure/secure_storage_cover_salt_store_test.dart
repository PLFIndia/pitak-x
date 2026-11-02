import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/infrastructure/secure_storage_cover_salt_store.dart';

/// The cover salt in secure storage: generated once on first use, and since
/// plan S11 replaceable by the backup adoption only (length-checked first).
void main() {
  late _FakeStorage storage;
  late SecureStorageCoverSaltStore store;

  setUp(() {
    storage = _FakeStorage();
    store = SecureStorageCoverSaltStore(storage: storage, random: Random(7));
  });

  test('first use generates 16 bytes once; later reads return them', () async {
    final first = await store.salt();
    expect(first, hasLength(16));
    expect(storage.writes, 1);
    expect(await store.salt(), first);
    expect(storage.writes, 1, reason: 'an existing salt is never rewritten');
  });

  test('replace stores exactly the given salt', () async {
    await store.salt();
    final next = List<int>.generate(16, (i) => 255 - i);
    final result = await store.replace(next);
    expect(result.isRight(), isTrue);
    expect(await store.salt(), next);
    expect(storage.values.values.single, base64Encode(next));
  });

  test(
    'replace refuses a wrong length or byte range and writes nothing',
    () async {
      for (final salt in [
        List<int>.filled(15, 1),
        List<int>.filled(17, 1),
        <int>[],
        [...List<int>.filled(15, 1), 256],
      ]) {
        final failure = (await store.replace(salt)).getLeft().toNullable();
        expect(failure, isA<ValidationFailure>(), reason: '$salt');
      }
      expect(storage.writes, 0);
    },
  );

  test('a platform write failure is a fixed StorageFailure', () async {
    storage.failWrite = true;
    final failure = (await store.replace(
      List<int>.filled(16, 9),
    )).getLeft().toNullable();
    expect(failure, isA<StorageFailure>());
    expect(failure.toString(), isNot(contains('private platform detail')));
  });
}

final class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  int writes = 0;
  bool failWrite = false;

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
    writes++;
    values[key] = value!;
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
}
