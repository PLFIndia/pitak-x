/// Wipeable holder for sensitive bytes (AGENTS.md §6.1).
///
/// Dart `String` is immutable, UTF-16, and cannot be reliably wiped from
/// the GC heap — so secrets (the user passphrase en route to the Rust
/// core, any transient key material on the Dart side) are held here as a
/// mutable `Uint8List` and zeroed on `dispose`.
///
/// Design adapted from:
///  - Kotlin `VaultPassphrase` (this repo's source app): exact-size byte
///    holder, zero-on-close, throw-after-close.
///  - SynapseNote `SecureMemory` (`core/crypto/SecureMemory.kt`): two-pass wipe
///    (random fill, then zero) to avoid leaving an all-zero region that betrays
///    where a key used to live.
///
/// NOTE (honest limitation, per PLAN.md threat notes): this is best-effort
/// on a GC runtime. The VM may have copied these bytes during a moving GC
/// before we wipe. The *vault key itself* never lives here — it lives only
/// inside the Rust core in `Zeroizing<>`. This holder only ever carries the
/// transient passphrase bytes on their way across the FFI boundary.
library;

import 'dart:math';
import 'dart:typed_data';

/// A mutable byte secret that zeroes itself on [dispose] and rejects use after.
final class SecretBytes {
  /// Wraps [_bytes] verbatim and takes ownership of it. The caller must not
  /// retain or mutate [_bytes] after handing it over.
  SecretBytes(this._bytes);

  /// Allocates a zero-filled secret of [length] bytes for the caller to fill
  /// in place (e.g. char-by-char passphrase entry).
  factory SecretBytes.filled(int length) => SecretBytes(Uint8List(length));

  final Uint8List _bytes;
  bool _disposed = false;

  static final Random _rng = Random.secure();

  /// Number of bytes held. Length is not secret.
  int get length {
    _checkAlive();
    return _bytes.length;
  }

  /// Runs [action] with scoped access to the raw bytes. Bytes must not be
  /// retained beyond [action] — they are owned by this holder and wiped on
  /// [dispose].
  R use<R>(R Function(Uint8List bytes) action) {
    _checkAlive();
    return action(_bytes);
  }

  /// Returns a defensive copy. Caller owns the copy and must wipe it.
  ///
  /// Prefer [useAsync] for FFI/await boundaries — it wipes the copy for you.
  Uint8List copyBytes() {
    _checkAlive();
    return Uint8List.fromList(_bytes);
  }

  /// Runs [action] with a defensive copy of the bytes, then WIPES the copy in
  /// a `finally` — success, failure, or thrown error alike (§6.1).
  ///
  /// This exists for async boundaries (FFI calls) where the callee needs a
  /// list it can hand across an await: the copy's lifetime is scoped to
  /// [action], so no un-wiped passphrase copy is left on the GC heap by a
  /// call site that forgot its cleanup. [action] must not retain the copy.
  Future<R> useAsync<R>(Future<R> Function(Uint8List bytes) action) async {
    _checkAlive();
    final copy = Uint8List.fromList(_bytes);
    try {
      return await action(copy);
    } finally {
      wipe(copy);
    }
  }

  /// Two-pass wipe (random fill, then zero) of an arbitrary [buffer]. For
  /// byte lists that arrive from outside [SecretBytes] ownership (e.g. FFI
  /// results) and must not linger on the heap.
  static void wipe(List<int> buffer) {
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = _rng.nextInt(256);
    }
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = 0;
    }
  }

  /// Two-pass wipe (random, then zero) and mark disposed. Idempotent.
  void dispose() {
    if (_disposed) return;
    wipe(_bytes);
    _disposed = true;
  }

  void _checkAlive() {
    if (_disposed) {
      throw StateError('SecretBytes used after dispose');
    }
  }

  /// Never leak the value through interpolation or logs (AGENTS.md §6.2).
  @override
  String toString() => 'SecretBytes(***)';
}
