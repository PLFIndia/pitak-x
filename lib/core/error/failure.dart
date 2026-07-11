/// Sealed failure hierarchy for the whole app (AGENTS.md §5).
///
/// Expected failures cross layers as `Either<Failure, T>` (fpdart), never as
/// thrown exceptions. The UI maps each variant to a safe, user-facing message;
/// raw exception text is never shown to users.
library;

/// Base type for every expected, typed failure in the domain/application layer.
///
/// All subtypes are immutable.
sealed class Failure {
  const Failure();
}

/// Input failed validation at a boundary (value object, use case, IPC arg).
final class ValidationFailure extends Failure {
  /// Creates a validation failure carrying a human-readable [message].
  const ValidationFailure(this.message);

  /// Why validation failed (safe to surface as a user hint).
  final String message;
}

/// A requested entity/row was not found.
final class NotFoundFailure extends Failure {
  /// Creates a not-found failure.
  const NotFoundFailure();
}

/// The supplied backup passphrase did not unwrap the vault blob.
///
/// Mirrors Kotlin `BackupRestore.Result.WrongPassphrase` — kept distinct from
/// [BackupCorruptFailure] so the UI can let the user retry rather than declare
/// the archive broken.
final class WrongPassphraseFailure extends Failure {
  /// Creates a wrong-passphrase failure.
  const WrongPassphraseFailure();
}

/// The backup archive is structurally invalid or its crypto blob is corrupt.
///
/// Mirrors Kotlin `BackupRestore.Result.Failed` / `SetBlobResult.InvalidFormat`.
final class BackupCorruptFailure extends Failure {
  /// Creates a corrupt-archive failure with a short diagnostic [reason].
  const BackupCorruptFailure(this.reason);

  /// Short diagnostic (not shown verbatim to users).
  final String reason;
}

/// The archive's schema version is newer than this build can read.
///
/// Mirrors Kotlin `BackupRestore.Result.SchemaTooNew`.
final class SchemaTooNewFailure extends Failure {
  /// Creates a schema-too-new failure for the given [schemaVersion].
  const SchemaTooNewFailure(this.schemaVersion);

  /// The archive's declared schema version, newer than this build supports.
  final int schemaVersion;
}

/// A cryptographic operation failed (KDF, AEAD, or SQLCipher open).
final class CryptoFailure extends Failure {
  /// Creates a crypto failure with a short diagnostic [reason].
  const CryptoFailure(this.reason);

  /// Short diagnostic (not shown verbatim to users).
  final String reason;
}

/// A persistence/storage operation failed (Drift, file IO, secure storage).
final class StorageFailure extends Failure {
  /// Creates a storage failure with a short diagnostic [reason].
  const StorageFailure(this.reason);

  /// Short diagnostic (not shown verbatim to users).
  final String reason;
}

/// A network operation failed (unreachable host, timeout, or an HTTP-level
/// error from a remote API). The UI shows a generic "check your connection"
/// message — transport detail never reaches the user verbatim.
final class NetworkFailure extends Failure {
  /// Creates a network failure.
  const NetworkFailure();
}

/// An unexpected error (a bug). Caller should log, wipe sensitive state, and
/// fail closed — never expose [debugReason] to the user.
final class UnexpectedFailure extends Failure {
  /// Creates an unexpected (bug) failure with an internal [debugReason].
  const UnexpectedFailure(this.debugReason);

  /// Internal-only reason; never surface to the user.
  final String debugReason;
}
