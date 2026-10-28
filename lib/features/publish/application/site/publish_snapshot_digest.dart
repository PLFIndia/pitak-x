/// Canonical, operation-independent identity of a publish snapshot (R4).
///
/// Replacement confirmation compares this digest after rebuilding from current
/// local data. Ordinary assets use their content hashes. The two JSON documents
/// with operation timestamps are canonicalized without those fields, so a new
/// clock alone never invalidates confirmation while real content edits do.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// Reads an already-spooled artifact by path, or null when it is unavailable.
typedef PublishArtifactBytesReader = Future<List<int>?> Function(String path);

/// Computes the one blessed replacement-confirmation digest.
abstract final class PublishSnapshotDigest {
  /// Fixed refusal for an inconsistent or uncanonicalizable snapshot.
  static const String failedMessage =
      'Could not confirm the publish snapshot. Nothing was published.';

  /// Returns the canonical SHA-256 digest, or a typed no-write failure.
  static Future<Either<Failure, String>> of(
    PublishSnapshot snapshot, {
    PublishArtifactBytesReader? readBytes,
  }) async {
    try {
      final sections = <Map<String, Object?>>[];
      for (final section in snapshot.sections) {
        sections.add({
          'name': section.section.name,
          'files': await _fileIdentities(section.files, readBytes),
        });
      }
      final canonical = _canonical(sections);
      final bytes = utf8.encode(jsonEncode(canonical));
      return right(sha256.convert(bytes).toString());
    } on FormatException {
      return const Left(ValidationFailure(failedMessage));
    } on _DigestInputException {
      return const Left(ValidationFailure(failedMessage));
    }
  }

  static Future<List<Map<String, Object?>>> _fileIdentities(
    List<PublishFile> files,
    PublishArtifactBytesReader? readBytes,
  ) async {
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));
    final seen = <String>{};
    final identities = <Map<String, Object?>>[];
    for (final file in sorted) {
      if (!seen.add(file.path)) throw const _DigestInputException();
      identities.add({
        'path': file.path,
        'content': await _contentIdentity(file, readBytes),
      });
    }
    return identities;
  }

  static Future<String> _contentIdentity(
    PublishFile file,
    PublishArtifactBytesReader? readBytes,
  ) async {
    if (file.gitSha.isEmpty) throw const _DigestInputException();
    final volatileField = switch (file.path) {
      CatalogueSectionBuilder.booksJsonPath => 'exportedAt',
      CatalogueSectionBuilder.libraryJsonPath => 'updatedAt',
      _ => null,
    };
    if (volatileField == null) return file.gitSha;
    final bytes = file.bytes.isNotEmpty
        ? file.bytes
        : await readBytes?.call(file.path);
    if (bytes == null || bytes.isEmpty) {
      throw const _DigestInputException();
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const _DigestInputException();
    final withoutTimestamp = <Object?, Object?>{
      for (final entry in decoded.entries)
        if (entry.key != volatileField) entry.key: entry.value,
    };
    final canonical = _canonical(withoutTimestamp);
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = <String>[];
      for (final key in value.keys) {
        if (key is! String) throw const _DigestInputException();
        keys.add(key);
      }
      keys.sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _canonical(item)];
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw const _DigestInputException();
  }
}

final class _DigestInputException implements Exception {
  const _DigestInputException();
}
