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

  /// True when a `borrowers.db` exists WITHOUT its wrapped-key blob (or the
  /// blob is blank). Such a DB can never be opened — nobody holds its key —
  /// and, left alone, it permanently blocks creating a new vault (the Rust
  /// core refuses to overwrite an existing file). Produced only by a crash
  /// or disk-full between `create_vault` and `writeBlob` (review 2026-09-03).
  @override
  bool hasOrphanDatabase() {
    if (!File(dbPath).existsSync()) return false;
    final blob = readBlob();
    return blob == null || blob.isEmpty;
  }

  /// Deletes an orphan `borrowers.db` (see [hasOrphanDatabase]) plus any stale
  /// biometric blob, so "Create vault" works again. Refuses to touch anything
  /// when a key blob exists (that would be a real vault — never delete it).
  /// Idempotent.
  @override
  void discardOrphanDatabase() {
    if (!hasOrphanDatabase()) return;
    final db = File(dbPath);
    if (db.existsSync()) db.deleteSync();
    // A blank blob file (truncated write) is as useless as none — remove it so
    // the state is unambiguous.
    final blob = File(_blobPath);
    if (blob.existsSync()) blob.deleteSync();
    clearBioBlob();
  }

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
  ///
  /// ATOMIC (review 2026-09-03, Blocker): this file is the ONLY thing that
  /// turns the user's passphrase into the vault key. A plain in-place write
  /// truncates the file first, so a crash / kill / disk-full between the
  /// truncate and the write (e.g. mid change-passphrase) left an EMPTY blob
  /// and the vault was lost forever. We now write a sibling temp file, flush
  /// it, and `rename` it over the live path — rename is atomic on the same
  /// filesystem, so the live blob is always either the old one or the new
  /// one, never half-written. Throws [FileSystemException] on failure with the
  /// live blob untouched (temp cleaned up), so callers can fail closed.
  @override
  void writeBlob(String blob) => _atomicWrite(File(_blobPath), blob);

  /// Write-temp-then-rename for the two key-blob files (see [writeBlob]).
  void _atomicWrite(File target, String contents) {
    Directory(baseDir).createSync(recursive: true);
    final tmp = File('${target.path}.tmp');
    try {
      tmp
        ..writeAsStringSync(contents, flush: true)
        ..renameSync(target.path);
    } on FileSystemException {
      // Never leave a stray temp next to the live file.
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
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
  /// plain file. Atomic like [writeBlob].
  @override
  void writeBioBlob(String blob) => _atomicWrite(File(_bioBlobPath), blob);

  /// Installs an archive's vault pair into this EMPTY store (M02).
  ///
  /// The DB is copied (the source is a scratch file, possibly on another
  /// filesystem) and the blob is written + flushed. Nothing here is live yet:
  /// the store is rooted in a generation directory that only becomes active
  /// after every file in it exists and the pointer is switched. A failure
  /// throws and the caller discards the whole generation, so there is no
  /// partial state to roll back. Refuses (throws [StateError]) if any vault
  /// artifact already exists here — installing over a vault is never valid.
  @override
  void installRestored({required String dbSourcePath, required String blob}) {
    _requireEmpty('installRestored');
    Directory(baseDir).createSync(recursive: true);
    File(dbSourcePath).copySync(dbPath);
    File(_blobPath).writeAsStringSync(blob, flush: true);
  }

  /// Copies the existing vault of [source] into this EMPTY store (M02): the
  /// encrypted DB with any SQLite side files, the wrapped-key blob and the
  /// biometric blob, all byte-for-byte. The blob files are flushed. Refuses
  /// (throws [StateError]) if any vault artifact already exists here.
  @override
  void copyFrom(VaultArtifactsStore source) {
    _requireEmpty('copyFrom');
    Directory(baseDir).createSync(recursive: true);
    final sourceDb = File(source.dbPath);
    if (sourceDb.existsSync()) {
      sourceDb.copySync(dbPath);
      // A hot journal / WAL is part of the database's state after a crash;
      // leaving it behind would silently drop committed vault writes.
      for (final suffix in const ['-journal', '-wal', '-shm']) {
        final side = File('${source.dbPath}$suffix');
        if (side.existsSync()) side.copySync('$dbPath$suffix');
      }
    }
    final blob = source.readBlob();
    if (blob != null) File(_blobPath).writeAsStringSync(blob, flush: true);
    final bioBlob = source.readBioBlob();
    if (bioBlob != null) {
      File(_bioBlobPath).writeAsStringSync(bioBlob, flush: true);
    }
  }

  void _requireEmpty(String operation) {
    if (File(dbPath).existsSync() ||
        File(_blobPath).existsSync() ||
        File(_bioBlobPath).existsSync()) {
      throw StateError('$operation: a vault already exists in $baseDir');
    }
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
