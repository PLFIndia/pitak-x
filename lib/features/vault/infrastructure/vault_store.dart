/// At-rest persistence for the on-device vault (infrastructure, AGENTS §3.3).
///
/// Owns two artifacts under the app documents directory (Q-26b):
///  - `borrowers.db` — the SQLCipher-encrypted vault database (opaque to Dart;
///    only Rust ever holds its key).
///  - `vault_backup_blob` — the wrapped vault key, i.e.
///    `base64(salt).base64(iv).base64(ciphertext)`. This is ALREADY ciphertext
///    (Argon2id-AES-GCM over the user passphrase), so it is stored as a plain
///    file rather than in `flutter_secure_storage` — wrapping ciphertext a
///    second time buys no confidentiality (mirrors the Kotlin app's deliberate
///    choice to keep this blob in plain storage). The user passphrase, which is
///    the only thing that unlocks it, never touches disk.
///
/// This type does NO crypto and never sees the vault key. It is pure file IO:
/// "is a vault set up?", "read/persist the blob", "where is the DB?".
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';

/// Filenames for the persistent vault artifacts (under the app docs dir).
const String _dbFileName = 'borrowers.db';
const String _blobFileName = 'vault_backup_blob';

/// The biometric-wrapped key blob (#34 B2). Like [_blobFileName] it is already
/// AES-GCM ciphertext (the vault key wrapped under the hardware-stored secret
/// S), so it is safe to keep as a plain file. Present only when biometric
/// unlock is enrolled; its absence means "not enrolled".
const String _bioBlobFileName = 'vault_biometric_blob';

/// Reads/writes the persistent vault's database path and wrapped-key blob.
final class VaultStore implements VaultArtifactsStore {
  /// Creates a store rooted at [baseDir] (typically the app documents dir).
  const VaultStore({required this.baseDir});

  /// Directory holding the vault artifacts.
  final String baseDir;

  @override
  String get dbPath => p.join(baseDir, _dbFileName);

  /// Absolute path to the wrapped-key blob file.
  String get _blobPath => p.join(baseDir, _blobFileName);

  /// Absolute path to the biometric-wrapped blob file (#34 B2).
  String get _bioBlobPath => p.join(baseDir, _bioBlobFileName);

  @override
  bool isInitialized() =>
      File(dbPath).existsSync() && File(_blobPath).existsSync();

  /// Reads the wrapped-key blob, or null if no vault is set up.
  ///
  /// Trims surrounding whitespace so a trailing newline (if any) never reaches
  /// the Rust blob parser, matching how the archive opener trims it.
  @override
  String? readBlob() {
    final f = File(_blobPath);
    if (!f.existsSync()) return null;
    return f.readAsStringSync().trim();
  }

  /// Persists the wrapped-key [blob]. Creates [baseDir] if needed. The blob is
  /// ciphertext, not a secret in plaintext — safe to write as a file.
  @override
  void writeBlob(String blob) {
    Directory(baseDir).createSync(recursive: true);
    File(_blobPath).writeAsStringSync(blob, flush: true);
  }

  /// Reads the biometric-wrapped blob (#34 B2), or null when biometric unlock
  /// is not enrolled. Trimmed like [readBlob].
  @override
  String? readBioBlob() {
    final f = File(_bioBlobPath);
    if (!f.existsSync()) return null;
    return f.readAsStringSync().trim();
  }

  /// True when biometric unlock is enrolled (a biometric blob exists). The
  /// secret S itself lives in the OS secure store, not here.
  @override
  bool hasBioBlob() => File(_bioBlobPath).existsSync();

  /// Persists the biometric-wrapped [blob] (#34 B2). Ciphertext — safe as a
  /// plain file.
  @override
  void writeBioBlob(String blob) {
    Directory(baseDir).createSync(recursive: true);
    File(_bioBlobPath).writeAsStringSync(blob, flush: true);
  }

  /// Stages a vault restored from a backup archive for a two-file commit
  /// (C1 + REVIEW_FINDINGS §4 restore-atomicity Major).
  ///
  /// Staging is the FALLIBLE half with ZERO live effects: the encrypted DB at
  /// [dbSourcePath] is copied to a sibling temp file next to [dbPath] (so the
  /// later rename happens on ONE filesystem, where rename is atomic), and the
  /// wrapped-key [blob] is written to a sibling temp file, flushed. Pattern
  /// borrowed from SQLite's write-temp-then-rename durability approach.
  ///
  /// The returned handle either [StagedVaultInstall.commit]s the pair onto the
  /// live paths or [StagedVaultInstall.abort]s, deleting the temps. Nothing
  /// about the live vault changes until `commit()`.
  ///
  /// Throws [FileSystemException] on any IO failure (partial temps are cleaned
  /// up first) so the caller can fail closed.
  @override
  FileStagedVaultInstall stageRestore({
    required String dbSourcePath,
    required String blob,
  }) {
    Directory(baseDir).createSync(recursive: true);
    final dbTmp = File('$dbPath.restore.tmp');
    final blobTmp = File('$_blobPath.restore.tmp');
    try {
      if (dbTmp.existsSync()) dbTmp.deleteSync();
      if (blobTmp.existsSync()) blobTmp.deleteSync();
      // Copy (source may live on a different filesystem, e.g. a scratch dir);
      // flush the blob so the bytes are on disk before commit() ever runs.
      File(dbSourcePath).copySync(dbTmp.path);
      blobTmp.writeAsStringSync(blob, flush: true);
    } on FileSystemException {
      // Leave no half-staged temps behind; staging must be all-or-nothing.
      if (dbTmp.existsSync()) dbTmp.deleteSync();
      if (blobTmp.existsSync()) blobTmp.deleteSync();
      rethrow;
    }
    return FileStagedVaultInstall._(
      store: this,
      dbTmp: dbTmp,
      blobTmp: blobTmp,
    );
  }

  /// Removes ONLY the biometric blob (disable biometric unlock). Idempotent;
  /// leaves the vault and its passphrase blob intact.
  @override
  void clearBioBlob() {
    final f = File(_bioBlobPath);
    if (f.existsSync()) f.deleteSync();
  }

  /// Deletes all artifacts (wipe / start-over path). Best-effort and
  /// idempotent: a missing file is not an error.
  @override
  void clear() {
    final db = File(dbPath);
    if (db.existsSync()) db.deleteSync();
    final blob = File(_blobPath);
    if (blob.existsSync()) blob.deleteSync();
    final bioBlob = File(_bioBlobPath);
    if (bioBlob.existsSync()) bioBlob.deleteSync();
  }
}

/// File-backed commit half of [VaultStore.stageRestore]'s two-file install
/// (implements the domain [StagedVaultInstall] contract).
///
/// Why this type exists (beginner note): replacing the vault means replacing
/// TWO files that only work as a pair — the encrypted DB and the wrapped key
/// that opens it. A crash between writing one and the other would leave a DB
/// nobody can ever open again. So we stage both as temps first (fallible, no
/// live effect), then swap them in with atomic renames here, rolling the key
/// blob back if the second rename fails.
final class FileStagedVaultInstall implements StagedVaultInstall {
  FileStagedVaultInstall._({
    required VaultStore store,
    required File dbTmp,
    required File blobTmp,
  }) : _store = store,
       _dbTmp = dbTmp,
       _blobTmp = blobTmp;

  final VaultStore _store;
  final File _dbTmp;
  final File _blobTmp;
  bool _done = false;

  /// Swaps the staged pair onto the live paths.
  ///
  /// Order and recovery:
  ///  1. the OLD blob (if any) is read into memory as a rollback value;
  ///  2. the staged blob is atomically renamed onto the live blob path;
  ///  3. the staged DB is atomically renamed onto the live DB path; if THIS
  ///     rename fails, the old blob is written back so the pre-restore vault
  ///     stays openable (fail closed — never a DB/key mismatch we created);
  ///  4. the biometric blob is cleared: it wrapped the PREVIOUS vault key, so
  ///     biometric unlock must be re-enrolled against the restored vault.
  ///
  /// Blob-first ordering: a crash between steps 2 and 3 leaves new-blob +
  /// old-DB, which re-running the restore from the same archive repairs — the
  /// narrowest window achievable without a cross-file transaction. Throws
  /// [FileSystemException] on failure (with the blob rollback applied) so the
  /// caller can fail closed. Must be called at most once.
  @override
  void commit() {
    if (_done) {
      throw StateError('StagedVaultInstall.commit called after completion');
    }
    final previousBlob = _store.readBlob();
    _blobTmp.renameSync(_store._blobPath);
    try {
      _dbTmp.renameSync(_store.dbPath);
    } on FileSystemException {
      // Roll the key blob back so the OLD vault (if any) stays openable.
      if (previousBlob != null) {
        File(_store._blobPath).writeAsStringSync(previousBlob, flush: true);
      } else {
        final f = File(_store._blobPath);
        if (f.existsSync()) f.deleteSync();
      }
      _done = true;
      rethrow;
    }
    _store.clearBioBlob();
    _done = true;
  }

  /// Deletes the staged temps without touching the live vault. Idempotent and
  /// safe to call after [commit] (the temps no longer exist then).
  @override
  void abort() {
    if (_dbTmp.existsSync()) _dbTmp.deleteSync();
    if (_blobTmp.existsSync()) _blobTmp.deleteSync();
    _done = true;
  }
}
