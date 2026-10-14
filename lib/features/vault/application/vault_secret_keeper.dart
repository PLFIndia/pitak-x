/// Holds the vault session's unlock secret and enforces its lifetime
/// (application layer, AGENTS.md §6.1; SOLID-PLAN S4).
///
/// Why a separate class: the wipe/fencing invariants are security-critical
/// and must be unit-testable without any vault IO or Riverpod. This is a
/// plain Dart object — the vault session controller delegates to it and
/// wires `ref.onDispose` to `dispose`.
///
/// The invariants (unchanged from the controller's old private fields):
///  - at most ONE held session secret (`current`); re-holding wipes the old;
///  - secrets of IN-FLIGHT operations are tracked (`trackPending`) so a
///    mid-flight `forget` (lock/dispose) wipes them too — a queued unlock
///    that loses the race can never leave its passphrase on the heap;
///  - `forget` bumps `generation`, so any operation that started before the
///    forget fails its next `isCurrent` check (the stale-operation fence);
///  - `dispose` additionally bumps `lifetime`, fencing builds (an old build
///    must not install its store into a new lifetime).
library;

import 'package:pitaka/core/crypto/secret_bytes.dart';

/// See the file header. Pure Dart: no Riverpod, no IO.
final class VaultSecretKeeper {
  /// The session unlock secret while unlocked; null when locked. EITHER the
  /// user passphrase OR the biometric secret S (both unwrap the same vault
  /// key from different blobs). Never exposed outside the controller; wiped
  /// on [forget]/[dispose] and on re-[hold].
  SecretBytes? get current => _current;
  SecretBytes? _current;

  /// The at-rest blob that [current] opens: the main passphrase blob, or the
  /// biometric blob when unlocked via biometrics. Writes and re-wraps MUST
  /// use this blob (paired with the held secret), not assume the passphrase
  /// blob — otherwise an S-unlocked session would fail to write.
  String? get activeBlob => _activeBlob;
  String? _activeBlob;

  /// Whether [current] is the biometric S (vs the user passphrase).
  bool get activeIsBiometric => _activeIsBiometric;
  bool _activeIsBiometric = false;

  /// Secrets owned by in-flight operations; wiped by [forget] even when
  /// [current] is null.
  final Set<SecretBytes> _pending = {};

  /// Session identity for operations: bumped on every [forget], so stale
  /// queued work fails its currency check. Read it when an operation STARTS,
  /// check `isCurrent(remembered)` after every await.
  int get generation => _generation;
  int _generation = 0;

  /// Session identity for BUILDS: bumped on [dispose] only, so a late
  /// `build()` future from before a dispose/rebuild cannot install its
  /// store. (A `lock()` bumps [generation] but not [lifetime] — the store
  /// is still valid across a lock.)
  int get lifetime => _lifetime;
  int _lifetime = 0;

  /// True after [dispose] until the controller's next `build()` calls
  /// [beginLifetime].
  bool get isDisposed => _isDisposed;
  bool _isDisposed = false;

  /// A new lifetime begins (called by the controller's `build()`).
  void beginLifetime() => _isDisposed = false;

  /// True when [generation] is the current one and the keeper is alive.
  bool isCurrent(int generation) => !_isDisposed && generation == _generation;

  /// True when [lifetime] is the current one and the keeper is alive.
  bool isCurrentLifetime(int lifetime) => !_isDisposed && lifetime == _lifetime;

  /// Holds [secret] as the session secret (with the [blob] it opens).
  /// Re-holding wipes the previous secret — no orphan bytes.
  void hold(SecretBytes secret, String blob, {required bool biometric}) {
    _current?.dispose();
    _current = secret;
    _activeBlob = blob;
    _activeIsBiometric = biometric;
  }

  /// Tracks an in-flight operation's secret so [forget] wipes it too.
  void trackPending(SecretBytes secret) => _pending.add(secret);

  /// Stops tracking [secret] and wipes it — UNLESS it is the held [current]
  /// (a successful unlock/hold now owns it; wiping it would lock the vault).
  void untrackPending(SecretBytes secret) {
    _pending.remove(secret);
    if (!identical(secret, _current)) secret.dispose();
  }

  /// Wipes the held secret and every pending secret, and bumps [generation]
  /// (stale-op fence). Called on lock, on a failed re-key, and from
  /// [dispose]. Statement order is load-bearing: the generation bump comes
  /// FIRST so a concurrent operation observes the fence before its secret
  /// disappears under it.
  void forget() {
    _generation++;
    _current?.dispose();
    _current = null;
    _activeBlob = null;
    _activeIsBiometric = false;
    for (final secret in _pending) {
      secret.dispose();
    }
    _pending.clear();
  }

  /// Terminal teardown (wired to `ref.onDispose` by the controller): mark
  /// disposed, bump the lifetime fence, and wipe everything. Fail closed
  /// (AGENTS §2.7).
  void dispose() {
    _isDisposed = true;
    _lifetime++;
    forget();
  }
}
