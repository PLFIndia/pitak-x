/// Unit tests for [VaultSecretKeeper] (vault session split by responsibility): the wipe/fencing
/// invariants that guard the vault session's secret lifetime, tested without
/// any vault IO or Riverpod.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/features/vault/application/vault_secret_keeper.dart';

SecretBytes _secret(List<int> bytes) => SecretBytes(Uint8List.fromList(bytes));

void main() {
  test('hold exposes the secret + blob; biometric flag recorded', () {
    final keeper = VaultSecretKeeper();
    final s = _secret([1, 2, 3]);
    keeper.hold(s, 'blob-main', biometric: false);

    expect(keeper.current, same(s));
    expect(keeper.activeBlob, 'blob-main');
    expect(keeper.activeIsBiometric, isFalse);
  });

  test('hold then forget: current is null, held secret is wiped '
      '(use throws), generation incremented', () {
    final keeper = VaultSecretKeeper();
    final s = _secret([9, 9, 9]);
    keeper.hold(s, 'blob', biometric: true);
    final before = keeper.generation;

    keeper.forget();

    expect(keeper.current, isNull);
    expect(keeper.activeBlob, isNull);
    expect(keeper.activeIsBiometric, isFalse);
    expect(() => s.use((b) => b), throwsStateError);
    expect(keeper.generation, before + 1);
  });

  test('pending secrets are wiped by forget even when current is null', () {
    final keeper = VaultSecretKeeper();
    final pending = _secret([4, 5, 6]);
    keeper
      ..trackPending(pending)
      ..forget();

    expect(() => pending.use((b) => b), throwsStateError);
  });

  test(
    'a pending secret that BECAME current is not wiped by untrackPending',
    () {
      final keeper = VaultSecretKeeper();
      final s = _secret([7, 7, 7]);
      // The full lifecycle: track → hold (successful unlock) → untrack.
      keeper
        ..trackPending(s)
        // Successful unlock: the incoming secret is now the held session
        // secret.
        ..hold(s, 'blob', biometric: false)
        ..untrackPending(s);

      // Still alive — it is the session secret now.
      expect(s.use((b) => b.length), 3);
      expect(keeper.current, same(s));
    },
  );

  test('untrackPending wipes a secret that was never held', () {
    final keeper = VaultSecretKeeper();
    final s = _secret([8]);
    keeper
      ..trackPending(s)
      ..untrackPending(s);

    expect(() => s.use((b) => b), throwsStateError);
  });

  test('re-hold replaces AND wipes the previous secret — no orphan bytes', () {
    final keeper = VaultSecretKeeper();
    final old = _secret([1]);
    final replacement = _secret([2]);
    keeper
      ..hold(old, 'blob-old', biometric: false)
      // Re-holding wipes the previous secret.
      ..hold(replacement, 'blob-new', biometric: true);

    expect(() => old.use((b) => b), throwsStateError);
    expect(keeper.current, same(replacement));
    expect(keeper.activeBlob, 'blob-new');
    expect(keeper.activeIsBiometric, isTrue);
  });

  test('isCurrent: false for a stale generation after any forget; false '
      'after dispose', () {
    final keeper = VaultSecretKeeper()..beginLifetime();
    final g = keeper.generation;
    expect(keeper.isCurrent(g), isTrue);

    keeper.forget();
    expect(keeper.isCurrent(g), isFalse);

    final g2 = keeper.generation;
    keeper.dispose();
    expect(keeper.isCurrent(g2), isFalse);
    expect(keeper.isDisposed, isTrue);
  });

  test('dispose bumps the lifetime fence; beginLifetime clears the disposed '
      'flag without reviving secrets', () {
    final keeper = VaultSecretKeeper()..beginLifetime();
    final l0 = keeper.lifetime;
    expect(keeper.isCurrentLifetime(l0), isTrue);

    final s = _secret([3, 3]);
    keeper
      ..hold(s, 'blob', biometric: false)
      ..dispose();

    expect(keeper.isCurrentLifetime(l0), isFalse);
    expect(keeper.lifetime, l0 + 1);
    expect(() => s.use((b) => b), throwsStateError);

    // A rebuild starts a new lifetime: alive again, still empty.
    keeper.beginLifetime();
    expect(keeper.isDisposed, isFalse);
    expect(keeper.current, isNull);
  });

  test('forget is safe to call when nothing is held or pending', () {
    final keeper = VaultSecretKeeper();
    final g = keeper.generation;
    keeper.forget();
    expect(keeper.generation, g + 1);
    expect(keeper.current, isNull);
  });
}
