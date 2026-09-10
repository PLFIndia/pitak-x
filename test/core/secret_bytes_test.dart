import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';

void main() {
  group('SecretBytes', () {
    test('use() exposes the wrapped bytes while alive', () {
      final secret = SecretBytes(Uint8List.fromList([1, 2, 3]));
      final sum = secret.use((b) => b.reduce((a, c) => a + c));
      expect(sum, 6);
      expect(secret.length, 3);
      secret.dispose();
    });

    test('is zeroed and rejects use after dispose (AGENTS.md §6.1)', () {
      final backing = Uint8List.fromList([9, 9, 9, 9]);
      final secret = SecretBytes(backing)..dispose();
      // Backing buffer wiped to zero.
      expect(backing.every((b) => b == 0), isTrue);
      // Any access after dispose throws.
      expect(() => secret.use((b) => b), throwsStateError);
      expect(() => secret.length, throwsStateError);
      expect(secret.copyBytes, throwsStateError);
    });

    test('dispose is idempotent', () {
      final secret = SecretBytes(Uint8List.fromList([5]))..dispose();
      expect(secret.dispose, returnsNormally);
    });

    test('copyBytes returns an independent copy', () {
      final secret = SecretBytes(Uint8List.fromList([7, 8]));
      final copy = secret.copyBytes();
      copy[0] = 0;
      // Mutating the copy does not affect the holder.
      expect(secret.use((b) => b[0]), 7);
      secret.dispose();
    });

    test('useAsync wipes the scoped copy after the call (§6.1)', () async {
      final secret = SecretBytes(Uint8List.fromList([4, 5, 6]));
      late Uint8List seen;
      final result = await secret.useAsync((bytes) async {
        seen = bytes; // retained ONLY to assert the wipe below
        expect(bytes, [4, 5, 6]);
        return 42;
      });
      expect(result, 42);
      // The copy handed to the action is zeroed once the call returns.
      expect(seen.every((b) => b == 0), isTrue);
      // The holder itself is untouched.
      expect(secret.use((b) => b[0]), 4);
      secret.dispose();
    });

    test('useAsync wipes the copy even when the action throws', () async {
      final secret = SecretBytes(Uint8List.fromList([4, 5, 6]));
      late Uint8List seen;
      await expectLater(
        secret.useAsync((bytes) async {
          seen = bytes;
          throw StateError('ffi boom');
        }),
        throwsStateError,
      );
      expect(seen.every((b) => b == 0), isTrue);
      secret.dispose();
    });

    test('useAsync after dispose throws', () async {
      final secret = SecretBytes(Uint8List.fromList([1]))..dispose();
      expect(() => secret.useAsync((b) async => 0), throwsStateError);
    });

    test('static wipe zeroes an arbitrary buffer', () {
      final buffer = <int>[1, 2, 3, 4];
      SecretBytes.wipe(buffer);
      expect(buffer.every((b) => b == 0), isTrue);
    });

    test('refuses a read-only buffer at construction (Session 13: a secret '
        'that cannot be wiped must fail loudly at the boundary, not at '
        'lock/dispose time)', () {
      // The shape of every platform-channel reply: the engine wraps replies
      // in `asUnmodifiableView()` and the codec returns a view over them.
      final readOnly = Uint8List.fromList([1, 2, 3]).asUnmodifiableView();
      expect(() => SecretBytes(readOnly), throwsArgumentError);
      // The documented remedy works and yields a wipeable holder.
      final owned = SecretBytes(Uint8List.fromList(readOnly));
      expect(owned.use((b) => b.toList()), [1, 2, 3]);
      expect(owned.dispose, returnsNormally);
    });

    test('accepts an empty buffer (nothing to wipe)', () {
      final secret = SecretBytes(Uint8List(0));
      expect(secret.length, 0);
      expect(secret.dispose, returnsNormally);
    });

    test('toString never leaks the value (AGENTS.md §6.2)', () {
      final secret = SecretBytes(Uint8List.fromList([1, 2, 3]));
      expect(secret.toString(), 'SecretBytes(***)');
      secret.dispose();
    });
  });
}
