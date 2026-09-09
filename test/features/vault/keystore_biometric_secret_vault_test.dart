import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/infrastructure/keystore_biometric_secret_vault.dart';

/// M08 regression suite for the hardware-bound biometric secret store.
///
/// The finding (astra-review.md M08) is STATIC: the old store kept S in
/// `flutter_secure_storage` in the clear and the only guard was a Dart
/// boolean from `local_auth`. These tests pin the properties the new store
/// must have so the regression can never silently return:
///
///  1. S never leaves Dart as a `String`; the channel carries `Uint8List`.
///  2. What lands in secure storage is CIPHERTEXT (the native seal output),
///     never S itself, and it is versioned under a NEW key.
///  3. `read()` cannot succeed without the native `open` round-trip — there is
///     no Dart-side path that decodes S from storage.
///  4. Every native error code maps to a typed `Failure`; the
///     `invalidated` code (Keystore key killed by a biometric re-enrolment)
///     maps to `BiometricInvalidatedFailure` so callers can fail closed and
///     wipe the now-useless artifacts.
///  5. A legacy plaintext `_v1` entry is deleted, never read as S.
///  6. Buffers handed to the channel are wiped after use.

/// In-memory secure storage: overrides only the four methods the store uses,
/// so the test never touches the flutter_secure_storage platform channel.
final class _FakeStorage extends FlutterSecureStorage {
  _FakeStorage({this.failWrites = false, this.failReads = false});

  final bool failWrites;
  final bool failReads;
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
  }) async {
    if (failReads) throw Exception('keystore unavailable');
    return values[key];
  }

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

/// Scripted stand-in for the Kotlin `BiometricSecretVault` channel handler.
///
/// "Seals" by XOR-ing with a fixed pad so the test can prove that storage
/// holds ciphertext ≠ S, and that `open` is the only way back. Records every
/// call and the exact argument types it received.
final class _FakeNative {
  _FakeNative(this.tester);

  final WidgetTester tester;
  final calls = <MethodCall>[];

  /// When set, every seal/open/destroy call fails with this PlatformException
  /// code (mirrors the Kotlin error contract).
  String? failWithCode;

  /// When true, the handler answers `null` for every call — exactly what the
  /// engine does for a channel with no registered native handler, which
  /// `MethodChannel` turns into a `MissingPluginException`.
  bool noNativeHandler = false;

  /// When set, `seal` answers this instead of a `{iv, ciphertext}` map
  /// ([nullReply] scripts a literal `null` reply).
  Object? malformedSealReply;
  static const Object nullReply = Object();

  /// When set, `open` answers this instead of the plaintext.
  Object? malformedOpenReply;

  /// When true, `destroy` fails with a PlatformException.
  bool failDestroy = false;

  /// The `secret` bytes received by `seal`. The codec has already serialised
  /// them by the time the handler runs, so this is a decoded copy — the
  /// buffer the STORE handed to the channel is checked via the SecretBytes it
  /// was copied from (see the wipe test).
  Uint8List? sealedInputSnapshot;

  static const _pad = 0x5A;
  static final _iv = Uint8List.fromList(List<int>.generate(12, (i) => i + 1));

  void install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      KeystoreBiometricSecretVault.channel,
      _handle,
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    if (noNativeHandler) throw MissingPluginException();
    if (failWithCode case final code?) {
      throw PlatformException(code: code, message: 'scripted');
    }
    switch (call.method) {
      case 'seal':
        final args = call.arguments as Map<Object?, Object?>;
        final secret = args['secret'];
        if (secret is! Uint8List) {
          throw PlatformException(
            code: 'failed',
            message:
                'test: secret must be Uint8List, got ${secret.runtimeType}',
          );
        }
        sealedInputSnapshot = Uint8List.fromList(secret);
        if (malformedSealReply case final reply?) {
          return identical(reply, nullReply) ? null : reply;
        }
        return <String, Object?>{
          'iv': _iv,
          'ciphertext': Uint8List.fromList(
            secret.map((b) => b ^ _pad).toList(),
          ),
        };
      case 'open':
        final args = call.arguments as Map<Object?, Object?>;
        final iv = args['iv'];
        final ct = args['ciphertext'];
        if (iv is! Uint8List || ct is! Uint8List) {
          throw PlatformException(
            code: 'failed',
            message: 'test: iv/ciphertext must be Uint8List',
          );
        }
        expect(iv, _iv);
        if (malformedOpenReply != null) return malformedOpenReply;
        return Uint8List.fromList(ct.map((b) => b ^ _pad).toList());
      case 'destroy':
        if (failDestroy) {
          throw PlatformException(code: 'failed', message: 'scripted');
        }
        return null;
    }
    throw PlatformException(code: 'failed', message: 'unknown method');
  }

  void uninstall() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      KeystoreBiometricSecretVault.channel,
      null,
    );
  }

  List<String> get methods => calls.map((c) => c.method).toList();
}

void main() {
  SecretBytes s(List<int> bytes) => SecretBytes(Uint8List.fromList(bytes));

  /// Builds a store + fake native handler; the handler is removed on teardown.
  ({KeystoreBiometricSecretVault store, _FakeNative native, _FakeStorage fake})
  harness(
    WidgetTester tester, {
    bool failWrites = false,
    bool failReads = false,
  }) {
    final native = _FakeNative(tester)..install();
    addTearDown(native.uninstall);
    final fake = _FakeStorage(failWrites: failWrites, failReads: failReads);
    return (
      store: KeystoreBiometricSecretVault(storage: fake),
      native: native,
      fake: fake,
    );
  }

  testWidgets('store seals S through the native channel as BYTES and '
      'persists only ciphertext under the v2 key', (tester) async {
    final h = harness(tester);
    final secret = s([1, 2, 3, 250]);
    final wrote = await h.store.store(secret);
    secret.dispose();

    expect(wrote.isRight(), isTrue, reason: 'store must succeed');
    expect(h.native.methods, ['seal']);
    // Argument crossed as Uint8List (never String) — checked by the fake.
    expect(h.native.sealedInputSnapshot, [1, 2, 3, 250]);
    // Exactly one entry, versioned key, and it is NOT S (nor base64 of S).
    expect(h.fake.values.keys.single, 'vault_biometric_secret_v2');
    final stored = h.fake.values.values.single;
    expect(stored, isNot(contains('AQID+g==')), reason: 'base64(S) leaked');
    expect(await h.store.hasSecret(), isTrue);
  });

  testWidgets('read releases S only via the native open round-trip', (
    tester,
  ) async {
    final h = harness(tester);
    final secret = s([9, 8, 7]);
    await h.store.store(secret);
    secret.dispose();
    h.native.calls.clear();

    final read = await h.store.read();
    read.match((f) => fail('unexpected failure: $f'), (released) {
      expect(released, isNotNull);
      expect(released!.use((b) => b), [9, 8, 7]);
      released.dispose();
    });
    expect(h.native.methods, ['open']);
    final args = h.native.calls.single.arguments as Map<Object?, Object?>;
    expect(args['iv'], isA<Uint8List>());
    expect(args['ciphertext'], isA<Uint8List>());
  });

  testWidgets('store never consumes or mutates the caller-owned secret, and '
      'hands the channel a scoped copy', (tester) async {
    final h = harness(tester);
    final secret = s([11, 22, 33, 44]);
    await h.store.store(secret);
    // The caller still owns S: usable and intact after store() returns (the
    // store worked on a SecretBytes.useAsync copy, which useAsync wipes in
    // its finally — covered by test/core/secret_bytes_test.dart).
    expect(secret.use((b) => b.toList()), [11, 22, 33, 44]);
    secret.dispose();
    expect(h.native.sealedInputSnapshot, [11, 22, 33, 44]);
  });

  testWidgets('read returns null when nothing is enrolled and never calls '
      'the native side', (tester) async {
    final h = harness(tester);
    final read = await h.store.read();
    read.match(
      (f) => fail('unexpected failure: $f'),
      (released) => expect(released, isNull),
    );
    expect(await h.store.hasSecret(), isFalse);
    expect(h.native.methods, isEmpty);
  });

  testWidgets('clear removes the ciphertext AND destroys the Keystore key', (
    tester,
  ) async {
    final h = harness(tester);
    final secret = s([5]);
    await h.store.store(secret);
    secret.dispose();
    h.native.calls.clear();

    final cleared = await h.store.clear();
    expect(cleared.isRight(), isTrue);
    expect(h.fake.values, isEmpty);
    expect(await h.store.hasSecret(), isFalse);
    expect(h.native.methods, ['destroy']);
  });

  testWidgets('clear is idempotent with nothing enrolled', (tester) async {
    final h = harness(tester);
    expect((await h.store.clear()).isRight(), isTrue);
    expect((await h.store.clear()).isRight(), isTrue);
  });

  group('native error codes map to typed failures (fail closed)', () {
    for (final (code, matcher) in <(String, TypeMatcher<Failure>)>[
      ('cancelled', isA<ValidationFailure>()),
      ('lockout', isA<ValidationFailure>()),
      ('unavailable', isA<ValidationFailure>()),
      ('busy', isA<ValidationFailure>()),
      ('failed', isA<CryptoFailure>()),
      ('invalidated', isA<BiometricInvalidatedFailure>()),
      ('some-unknown-code', isA<CryptoFailure>()),
    ]) {
      testWidgets('open → "$code"', (tester) async {
        final h = harness(tester);
        final secret = s([1, 2, 3]);
        await h.store.store(secret);
        secret.dispose();

        h.native.failWithCode = code;
        final read = await h.store.read();
        read.match(
          (f) => expect(f, matcher),
          (_) => fail('expected a failure for code $code'),
        );
        // The ciphertext stays where it was: the store itself never decides
        // to wipe enrolment artifacts — the session controller does, and only
        // for `invalidated` (tested in vault_session_controller_test.dart).
        expect(await h.store.hasSecret(), isTrue);
      });

      testWidgets('seal → "$code" persists nothing', (tester) async {
        final h = harness(tester);
        h.native.failWithCode = code;
        final secret = s([1, 2, 3]);
        final wrote = await h.store.store(secret);
        secret.dispose();
        wrote.match(
          (f) => expect(f, matcher),
          (_) => fail('expected a failure for code $code'),
        );
        expect(h.fake.values, isEmpty);
        expect(await h.store.hasSecret(), isFalse);
      });
    }
  });

  testWidgets('failure messages never contain secret bytes', (tester) async {
    final h = harness(tester);
    h.native.failWithCode = 'failed';
    final secret = s([0x41, 0x42, 0x43]); // "ABC" if it ever leaked as text
    final wrote = await h.store.store(secret);
    secret.dispose();
    wrote.match((f) {
      final text = switch (f) {
        CryptoFailure(:final reason) => reason,
        StorageFailure(:final reason) => reason,
        _ => f.toString(),
      };
      expect(text, isNot(contains('ABC')));
      expect(text, isNot(contains('65, 66, 67')));
    }, (_) => fail('expected failure'));
  });

  testWidgets('a legacy plaintext v1 entry is DELETED, never released as S, '
      'and reports not-enrolled', (tester) async {
    final h = harness(tester);
    // Pre-M08 layout: base64(S) in the clear under the v1 key.
    h.fake.values['vault_biometric_secret_v1'] = 'AQID';

    expect(await h.store.hasSecret(), isFalse);
    final read = await h.store.read();
    read.match(
      (f) => fail('unexpected failure: $f'),
      (released) => expect(released, isNull),
    );
    expect(h.fake.values.containsKey('vault_biometric_secret_v1'), isFalse);
    expect(h.native.methods, isEmpty, reason: 'no prompt for legacy data');
  });

  testWidgets('a failing secure-storage write maps to StorageFailure and '
      'does not leave a sealed secret without a key', (tester) async {
    final h = harness(tester, failWrites: true);
    final secret = s([1, 2, 3]);
    final wrote = await h.store.store(secret);
    secret.dispose();
    wrote.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a StorageFailure'),
    );
    // Seal ran, the write failed → the key must be destroyed so a stale
    // Keystore key never survives without ciphertext (fail closed, tidy).
    expect(h.native.methods, ['seal', 'destroy']);
  });

  testWidgets('a corrupt persisted record is rejected without calling open', (
    tester,
  ) async {
    final h = harness(tester);
    h.fake.values['vault_biometric_secret_v2'] = 'not-a-valid-record';
    final read = await h.store.read();
    read.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a StorageFailure'),
    );
    expect(h.native.methods, isEmpty);
  });

  testWidgets('a channel with no native handler (non-Android) fails closed '
      'as not-available, not as a crash', (tester) async {
    final h = harness(tester);
    h.native.noNativeHandler = true;
    final secret = s([1]);
    final wrote = await h.store.store(secret);
    secret.dispose();
    wrote.match(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected a failure without a native handler'),
    );
    expect(h.fake.values, isEmpty);

    // read() with a record but no native side: also a typed failure.
    h.native.noNativeHandler = false;
    final s2 = s([2]);
    await h.store.store(s2);
    s2.dispose();
    h.native.noNativeHandler = true;
    final read = await h.store.read();
    expect(read.isLeft(), isTrue);

    // clear() still removes the record (nothing to destroy natively).
    expect((await h.store.clear()).isRight(), isTrue);
    expect(h.fake.values, isEmpty);
  });

  group('defensive branches', () {
    testWidgets('a malformed seal reply persists nothing and destroys the '
        'key', (tester) async {
      for (final reply in <Object>[
        _FakeNative.nullReply,
        <String, Object?>{'iv': 'text', 'ciphertext': Uint8List(3)},
        <String, Object?>{'iv': Uint8List(5), 'ciphertext': Uint8List(3)},
        <String, Object?>{'iv': Uint8List(12), 'ciphertext': Uint8List(0)},
      ]) {
        final h = harness(tester);
        h.native.malformedSealReply = reply;
        final secret = s([1, 2, 3]);
        final wrote = await h.store.store(secret);
        secret.dispose();
        wrote.match(
          (f) => expect(f, isA<CryptoFailure>()),
          (_) => fail('expected CryptoFailure for reply $reply'),
        );
        expect(h.fake.values, isEmpty);
        expect(h.native.methods, ['seal', 'destroy']);
        h.native.uninstall();
      }
    });

    testWidgets('an empty open reply is a CryptoFailure, never an empty S', (
      tester,
    ) async {
      final h = harness(tester);
      final secret = s([1, 2, 3]);
      await h.store.store(secret);
      secret.dispose();
      h.native.malformedOpenReply = Uint8List(0);
      final read = await h.store.read();
      read.match(
        (f) => expect(f, isA<CryptoFailure>()),
        (_) => fail('expected CryptoFailure'),
      );
    });

    testWidgets('a failing secure-storage read is a StorageFailure and '
        'hasSecret reports false (fail closed)', (tester) async {
      final h = harness(tester, failReads: true);
      final read = await h.store.read();
      read.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected StorageFailure'),
      );
      expect(h.native.methods, isEmpty);
    });

    testWidgets('a record with undecodable base64 is rejected without open', (
      tester,
    ) async {
      final h = harness(tester);
      h.fake.values['vault_biometric_secret_v2'] = 'v2:@@@:###';
      final read = await h.store.read();
      read.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected StorageFailure'),
      );
      expect(h.native.methods, isEmpty);
    });

    testWidgets('clear reports a failed key destroy (record already gone)', (
      tester,
    ) async {
      final h = harness(tester);
      final secret = s([1]);
      await h.store.store(secret);
      secret.dispose();
      h.native.failDestroy = true;
      final cleared = await h.store.clear();
      cleared.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected StorageFailure'),
      );
      // The record is removed FIRST so a half-cleared state can never be
      // "enrolled with an unopenable key".
      expect(h.fake.values, isEmpty);
    });

    testWidgets('seal succeeded but the write failed and destroy also failed: '
        'the write failure wins, nothing persisted', (tester) async {
      final h = harness(tester, failWrites: true);
      h.native.failDestroy = true;
      final secret = s([1]);
      final wrote = await h.store.store(secret);
      secret.dispose();
      wrote.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected StorageFailure'),
      );
      expect(h.fake.values, isEmpty);
    });
  });
}
