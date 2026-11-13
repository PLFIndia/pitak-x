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

  /// True when the encrypted DB exists but its wrapped-key blob does not (a
  /// half-created vault after a crash). Nobody can open such a DB; the
  /// session controller discards it so a new vault can be created.
  bool hasOrphanDatabase();

  /// Deletes an orphan DB (see [hasOrphanDatabase]). Must be a no-op when a
  /// key blob exists — a real vault is never deleted here. Idempotent.
  void discardOrphanDatabase();

  /// True when a SQLite side file (`-journal`, `-wal` or `-shm`) lies next
  /// to the vault database (backup rework BR4 rider 2).
  ///
  /// Why it matters (beginner note): SQLite keeps such a file while it
  /// writes, and removes it when the write is done. A side file therefore
  /// means one of two things: a write is under way right now, or a write
  /// was cut off (the app was killed in the middle of it) and has not been
  /// tidied up yet. In both cases the database file ALONE is not a whole
  /// database, and a copy of it must not be trusted. Opening the vault
  /// (unlocking it) tidies up a cut-off write.
  ///
  /// The check cannot tell a side file that matters from one SQLite would
  /// simply throw away, so any of them counts (fail closed).
  bool hasUnfinishedWrite();

  /// Copies the encrypted vault database, as it is on disk right now, to
  /// [targetPath]: a file in a folder the caller owns (backup rework BR4).
  ///
  /// The backup packs this copy instead of the live file, because nothing
  /// else can write the copy while it is being read. Only the main database
  /// file is copied, and the copy is the same ciphertext as the original.
  /// The caller makes sure that no vault operation runs meanwhile
  /// (`VaultIdleGate`) and that [hasUnfinishedWrite] is false.
  ///
  /// Completes with an error on IO failure (for example when the database
  /// has vanished), so the caller can fail closed.
  Future<void> snapshotDatabaseTo(String targetPath);

  /// Reads the wrapped-key blob, or null if no vault is set up.
  String? readBlob();

  /// Persists the wrapped-key [blob] (ciphertext — safe at rest). Must be
  /// atomic (temp + rename): the live blob is never left half-written. Throws
  /// on IO failure so the caller can fail closed.
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

  /// Installs a vault restored from a backup archive — the encrypted DB at
  /// [dbSourcePath] plus its wrapped-key [blob] — into THIS store, which must
  /// be empty (M02: restore builds a brand-new data generation and only ever
  /// installs into that fresh directory; the live vault is never written).
  /// No biometric blob is written: the old one wrapped the previous key.
  ///
  /// Throws on IO failure, or if a vault already exists here, so the caller
  /// can fail closed and discard the whole generation.
  void installRestored({required String dbSourcePath, required String blob});

  /// Copies every artifact of [source] (encrypted DB with any SQLite side
  /// files, wrapped-key blob, biometric blob) into THIS empty store (M02: a
  /// vault-free restore carries the device's existing vault into the new
  /// generation unchanged). The caller must guarantee no vault operation is
  /// in flight (the session FIFO does).
  ///
  /// Throws on IO failure, or if a vault already exists here.
  void copyFrom(VaultArtifactsStore source);
}
