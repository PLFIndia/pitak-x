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

/// Filenames for the persistent vault artifacts (under the app docs dir).
const String _dbFileName = 'borrowers.db';
const String _blobFileName = 'vault_backup_blob';

/// The biometric-wrapped key blob (#34 B2). Like [_blobFileName] it is already
/// AES-GCM ciphertext (the vault key wrapped under the hardware-stored secret
/// S), so it is safe to keep as a plain file. Present only when biometric
/// unlock is enrolled; its absence means "not enrolled".
const String _bioBlobFileName = 'vault_biometric_blob';

/// Reads/writes the persistent vault's database path and wrapped-key blob.
final class VaultStore {
  /// Creates a store rooted at [baseDir] (typically the app documents dir).
  const VaultStore({required this.baseDir});

  /// Directory holding the vault artifacts.
  final String baseDir;

  /// Absolute path to the encrypted vault database.
  String get dbPath => p.join(baseDir, _dbFileName);

  /// Absolute path to the wrapped-key blob file.
  String get _blobPath => p.join(baseDir, _blobFileName);

  /// Absolute path to the biometric-wrapped blob file (#34 B2).
  String get _bioBlobPath => p.join(baseDir, _bioBlobFileName);

  /// True when a vault has been created on this device (both the DB and its
  /// wrapped-key blob exist). Either missing means "not set up".
  bool isInitialized() =>
      File(dbPath).existsSync() && File(_blobPath).existsSync();

  /// Reads the wrapped-key blob, or null if no vault is set up.
  ///
  /// Trims surrounding whitespace so a trailing newline (if any) never reaches
  /// the Rust blob parser, matching how the archive opener trims it.
  String? readBlob() {
    final f = File(_blobPath);
    if (!f.existsSync()) return null;
    return f.readAsStringSync().trim();
  }

  /// Persists the wrapped-key [blob]. Creates [baseDir] if needed. The blob is
  /// ciphertext, not a secret in plaintext — safe to write as a file.
  void writeBlob(String blob) {
    Directory(baseDir).createSync(recursive: true);
    File(_blobPath).writeAsStringSync(blob, flush: true);
  }

  /// Reads the biometric-wrapped blob (#34 B2), or null when biometric unlock
  /// is not enrolled. Trimmed like [readBlob].
  String? readBioBlob() {
    final f = File(_bioBlobPath);
    if (!f.existsSync()) return null;
    return f.readAsStringSync().trim();
  }

  /// True when biometric unlock is enrolled (a biometric blob exists). The
  /// secret S itself lives in the OS secure store, not here.
  bool hasBioBlob() => File(_bioBlobPath).existsSync();

  /// Persists the biometric-wrapped [blob] (#34 B2). Ciphertext — safe as a
  /// plain file.
  void writeBioBlob(String blob) {
    Directory(baseDir).createSync(recursive: true);
    File(_bioBlobPath).writeAsStringSync(blob, flush: true);
  }

  /// Installs a vault restored from a backup archive (C1).
  ///
  /// Atomically replaces the at-rest vault with the encrypted DB at
  /// [dbSourcePath] and its matching wrapped-key [blob]:
  ///  1. the DB is copied to a sibling temp file then `rename`d onto [dbPath]
  ///     (rename is atomic on a single filesystem — a crash mid-install can
  ///     never leave a half-written `borrowers.db`); borrowed from SQLite's
  ///     own write-temp-then-rename durability pattern;
  ///  2. the [blob] is persisted (it is the passphrase-wrapped key for THIS
  ///     DB — without it the restored DB cannot be unlocked);
  ///  3. the biometric blob is cleared: the old `blob_bio` wrapped the PREVIOUS
  ///     device key, which the restored vault no longer uses, so biometric
  ///     unlock must be re-enrolled against the restored vault.
  ///
  /// Throws [FileSystemException] on any IO failure so the caller can fail
  /// closed (a restore that can't persist the vault must NOT report success).
  void installRestored({required String dbSourcePath, required String blob}) {
    Directory(baseDir).createSync(recursive: true);
    final tmp = File('$dbPath.restore.tmp');
    if (tmp.existsSync()) tmp.deleteSync();
    // Copy first (source may live on a different filesystem, e.g. a scratch
    // dir), then atomically rename onto the live path on THIS filesystem.
    File(dbSourcePath).copySync(tmp.path);
    tmp.renameSync(dbPath);
    File(_blobPath).writeAsStringSync(blob, flush: true);
    clearBioBlob();
  }

  /// Removes ONLY the biometric blob (disable biometric unlock). Idempotent;
  /// leaves the vault and its passphrase blob intact.
  void clearBioBlob() {
    final f = File(_bioBlobPath);
    if (f.existsSync()) f.deleteSync();
  }

  /// Deletes all artifacts (wipe / start-over path). Best-effort and
  /// idempotent: a missing file is not an error.
  void clear() {
    final db = File(dbPath);
    if (db.existsSync()) db.deleteSync();
    final blob = File(_blobPath);
    if (blob.existsSync()) blob.deleteSync();
    final bioBlob = File(_bioBlobPath);
    if (bioBlob.existsSync()) bioBlob.deleteSync();
  }
}
