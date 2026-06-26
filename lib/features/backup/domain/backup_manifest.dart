/// On-disk manifest for a Pitaka backup archive. Pure Dart port of Kotlin
/// `BackupManifest` (source app).
///
/// `schemaVersion` is read FIRST; restore refuses cleanly on
/// `schemaVersion > knownSchemaVersion`. The `hasX` booleans are forward-compat
/// flags: a future archive that intentionally omits a file sets the flag false
/// so restore knows it's absent-by-design rather than corrupt.
library;

import 'dart:convert';

/// Parsed backup-archive manifest.
class BackupManifest {
  /// Creates a manifest.
  const BackupManifest({
    required this.exportedAt,
    this.schemaVersion = knownSchemaVersion,
    this.hasBooks = true,
    this.hasWishlist = true,
    this.hasBorrowers = true,
    this.hasBackupBlob = true,
    this.hasCovers = false,
    this.backupHint,
  });

  /// Highest archive schema this build can restore (Kotlin
  /// `KNOWN_SCHEMA_VERSION = 1`).
  static const int knownSchemaVersion = 1;

  /// Archive schema version. Refuse restore when greater than
  /// [knownSchemaVersion].
  final int schemaVersion;

  /// Epoch millis the archive was exported.
  final int exportedAt;

  /// Whether the archive contains `books.db`.
  final bool hasBooks;

  /// Whether the archive contains `wishlist.db`.
  final bool hasWishlist;

  /// Whether the archive contains `borrowers.db`.
  final bool hasBorrowers;

  /// Whether the archive contains the encrypted `backup_blob`.
  final bool hasBackupBlob;

  /// Whether the archive bundles `cover_*` entries.
  final bool hasCovers;

  /// Optional user-facing passphrase hint.
  final String? backupHint;

  /// Parses [jsonText] into a manifest, or null if it is not a valid object.
  ///
  /// Tolerant of missing optional fields (defaults applied), but requires the
  /// JSON to be a parseable object. Never throws.
  static BackupManifest? tryParse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    return BackupManifest(
      schemaVersion: _asInt(decoded['schemaVersion']) ?? knownSchemaVersion,
      exportedAt: _asInt(decoded['exportedAt']) ?? 0,
      hasBooks: _asBool(decoded['hasBooks']) ?? true,
      hasWishlist: _asBool(decoded['hasWishlist']) ?? true,
      hasBorrowers: _asBool(decoded['hasBorrowers']) ?? true,
      hasBackupBlob: _asBool(decoded['hasBackupBlob']) ?? true,
      hasCovers: _asBool(decoded['hasCovers']) ?? false,
      backupHint: decoded['backupHint'] is String
          ? decoded['backupHint'] as String
          : null,
    );
  }

  /// Serializes this manifest to the canonical JSON shape (matches the Kotlin
  /// `BackupManifest` field names so the original app can read our backups).
  /// `backupHint` is omitted when null. Pretty-printed with a 2-space indent,
  /// mirroring the Kotlin writer.
  String toJson() {
    final map = <String, Object?>{
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt,
      'hasBooks': hasBooks,
      'hasWishlist': hasWishlist,
      'hasBorrowers': hasBorrowers,
      'hasBackupBlob': hasBackupBlob,
      'hasCovers': hasCovers,
      if (backupHint != null) 'backupHint': backupHint,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static bool? _asBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return null;
  }
}
