/// At-rest vault artifact persistence port (domain, AGENTS.md §3.3).
///
/// Declared in domain so the application layer (session controller, restore)
/// depends on this contract, not on the file-IO implementation
/// (`infrastructure/vault_store.dart`). The store owns three artifacts:
///  - the SQLCipher-encrypted vault database (opaque to Dart);
///  - the passphrase-wrapped key blob (already ciphertext);
///  - the optional biometric-wrapped key blob.
///
/// No crypto happens behind this interface and the vault key never crosses
/// it — only ciphertext blobs and file locations.
library;

/// Reads/writes the persistent vault's database path and wrapped-key blobs.
abstract interface class VaultArtifactsStore {
  /// Absolute path to the encrypted vault database.
  String get dbPath;

  /// True when a vault has been created on this device (both the DB and its
  /// wrapped-key blob exist). Either missing means "not set up".
  bool isInitialized();

  /// Reads the wrapped-key blob, or null if no vault is set up.
  String? readBlob();

  /// Persists the wrapped-key [blob] (ciphertext — safe at rest).
  void writeBlob(String blob);

  /// Reads the biometric-wrapped blob, or null when biometric unlock is not
  /// enrolled.
  String? readBioBlob();

  /// True when biometric unlock is enrolled (a biometric blob exists).
  bool hasBioBlob();

  /// Persists the biometric-wrapped [blob] (ciphertext — safe at rest).
  void writeBioBlob(String blob);

  /// Removes ONLY the biometric blob (disable biometric unlock). Idempotent.
  void clearBioBlob();

  /// Deletes all artifacts (wipe / start-over path). Idempotent.
  void clear();

  /// Stages a restored vault (encrypted DB at [dbSourcePath] + its wrapped-key
  /// [blob]) for a two-file commit. Staging has ZERO live effects; the
  /// returned handle either commits the pair atomically or aborts.
  ///
  /// Throws on IO failure so the caller can fail closed.
  StagedVaultInstall stageRestore({
    required String dbSourcePath,
    required String blob,
  });
}

/// The commit half of [VaultArtifactsStore.stageRestore]'s two-file install.
///
/// Why this exists (beginner note): replacing the vault means replacing TWO
/// files that only work as a pair — the encrypted DB and the wrapped key that
/// opens it. A crash between writing one and the other would leave a DB
/// nobody can ever open again, so both are staged first and swapped in
/// together here.
abstract interface class StagedVaultInstall {
  /// Swaps the staged pair onto the live paths (blob first, DB second, with
  /// blob rollback if the DB swap fails). Throws on failure so the caller can
  /// fail closed. Must be called at most once.
  void commit();

  /// Deletes the staged temps without touching the live vault. Idempotent.
  void abort();
}
