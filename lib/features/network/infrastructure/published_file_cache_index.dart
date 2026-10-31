/// The on-disk index of saved published files (network infrastructure;
/// ADR 0018). Used only by `FilePublishedFileCache`.
///
/// One small JSON file, `index.json`, describes every saved copy:
///
/// ```json
/// {"version": 1, "libraries": {
///   "<64 hex: SHA-256 of the site URL>": {
///     "lastOpenedAt": 1730300000000,
///     "files": {"catalogue": {"sha256": "<64 hex>", "size": 1234,
///                             "checkedAt": 1730300000000,
///                             "validator": "\"689c7eef-386e\""}}}}}
/// ```
///
/// Why the site URL is stored only as a hash (beginner note): the hash is a
/// fixed-length, path-safe folder name, and the index does not need to repeat
/// the user's saved-library list, which already lives in the database.
///
/// Decoding is strict and fail-closed. A library key must be exactly 64
/// lowercase hex characters — the key becomes a folder name, so this check
/// is what stops a tampered index from pointing outside the cache folder
/// (`../`). An entry with any invalid field is dropped (its file is then an
/// orphan the next sweep deletes); a document that is not a version-1 index at
/// all decodes to null and the caller wipes the whole cache.
library;

import 'dart:convert';

import 'package:pitaka/core/network/entity_tag.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';

/// Matches a lowercase hex SHA-256 (library keys and content hashes).
final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// One saved file inside one library's folder.
final class CachedFileEntry {
  /// Creates an entry from already-validated parts.
  const CachedFileEntry({
    required this.sha256,
    required this.size,
    required this.checkedAt,
    this.validator,
  });

  /// Lowercase hex SHA-256 of the saved bytes.
  final String sha256;

  /// Byte length of the saved file.
  final int size;

  /// Epoch ms when the host last confirmed the copy current.
  final int checkedAt;

  /// The host's entity tag, or null.
  final String? validator;

  /// This entry with a new confirmation time.
  CachedFileEntry confirmedAt(int checkedAt) => CachedFileEntry(
    sha256: sha256,
    size: size,
    checkedAt: checkedAt,
    validator: validator,
  );

  /// The JSON shape described in the file header.
  Map<String, Object?> toJson() => {
    'sha256': sha256,
    'size': size,
    'checkedAt': checkedAt,
    if (validator != null) 'validator': validator,
  };

  /// Parses one entry; null when any field is missing or invalid.
  static CachedFileEntry? fromJson(Object? json, {required int maxSize}) {
    if (json is! Map<String, dynamic>) return null;
    final sha = json['sha256'];
    final size = json['size'];
    final checkedAt = json['checkedAt'];
    final validator = json['validator'];
    if (sha is! String || !_sha256Hex.hasMatch(sha)) return null;
    if (size is! int || size < 0 || size > maxSize) return null;
    if (checkedAt is! int || checkedAt < 0) return null;
    if (validator != null &&
        (validator is! String || EntityTag.sanitize(validator) != validator)) {
      return null;
    }
    return CachedFileEntry(
      sha256: sha,
      size: size,
      checkedAt: checkedAt,
      validator: validator as String?,
    );
  }
}

/// Everything saved for one library.
final class CachedLibraryEntry {
  /// Creates a library entry. [files] is owned (and mutated) by the index.
  CachedLibraryEntry({required this.lastOpenedAt, required this.files});

  /// Epoch ms the user last opened this library — the eviction order.
  int lastOpenedAt;

  /// The saved files, by kind.
  final Map<PublishedFileKind, CachedFileEntry> files;

  /// Bytes this library occupies (its saved files only).
  int get totalBytes => files.values.fold(0, (sum, entry) => sum + entry.size);
}

/// The whole index: a mutable working copy, loaded and saved under the
/// store's serial queue so two operations never edit it at the same time.
final class PublishedFileCacheIndex {
  /// Creates an index over [libraries] (empty by default).
  PublishedFileCacheIndex([Map<String, CachedLibraryEntry>? libraries])
    : libraries = libraries ?? {};

  /// The format version this build reads and writes.
  static const int version = 1;

  /// Saved libraries by key (SHA-256 hex of the site URL).
  final Map<String, CachedLibraryEntry> libraries;

  /// True when [key] is a well-formed library key (safe as a folder name).
  static bool isValidKey(String key) => _sha256Hex.hasMatch(key);

  /// Bytes all saved copies occupy together.
  int get totalBytes =>
      libraries.values.fold(0, (sum, library) => sum + library.totalBytes);

  /// Encodes the JSON document described in the file header.
  String encode() => jsonEncode({
    'version': version,
    'libraries': {
      for (final MapEntry(:key, :value) in libraries.entries)
        key: {
          'lastOpenedAt': value.lastOpenedAt,
          'files': {
            for (final file in value.files.entries)
              file.key.name: file.value.toJson(),
          },
        },
    },
  });

  /// Decodes [text]; null when it is not a version-1 index at all. Invalid
  /// libraries/entries inside a valid document are dropped, not fatal.
  /// [maxFileSize] bounds each entry's declared size.
  static PublishedFileCacheIndex? decode(
    String text, {
    required int maxFileSize,
  }) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    if (json['version'] != version) return null;
    final rawLibraries = json['libraries'];
    if (rawLibraries is! Map<String, dynamic>) return null;

    final libraries = <String, CachedLibraryEntry>{};
    for (final MapEntry(:key, :value) in rawLibraries.entries) {
      if (!isValidKey(key) || value is! Map<String, dynamic>) continue;
      final lastOpenedAt = value['lastOpenedAt'];
      final rawFiles = value['files'];
      if (lastOpenedAt is! int || lastOpenedAt < 0) continue;
      if (rawFiles is! Map<String, dynamic>) continue;
      final files = <PublishedFileKind, CachedFileEntry>{};
      for (final kind in PublishedFileKind.values) {
        final entry = CachedFileEntry.fromJson(
          rawFiles[kind.name],
          maxSize: maxFileSize,
        );
        if (entry != null) files[kind] = entry;
      }
      if (files.isEmpty) continue;
      libraries[key] = CachedLibraryEntry(
        lastOpenedAt: lastOpenedAt,
        files: files,
      );
    }
    return PublishedFileCacheIndex(libraries);
  }
}
