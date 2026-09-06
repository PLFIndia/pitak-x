import 'dart:io';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:uuid/uuid.dart';

/// Writes operation-owned files, never using source names as destinations.
final class FileBundleCoverStore implements BundleCoverFiles {
  /// Creates the store in app-private storage. [newId] is a test seam.
  FileBundleCoverStore({required this.coversDir, String Function()? newId})
    : _newId = newId ?? const Uuid().v4;

  /// The same covers directory used by rendering and backup.
  final String coversDir;
  final String Function() _newId;

  @override
  BundleCoverBatch begin() => _FileBatch(coversDir, _newId);
}

final class _FileBatch implements BundleCoverBatch {
  _FileBatch(this._directory, this._newId);
  final String _directory;
  final String Function() _newId;
  final Map<String, File> _owned = {};
  bool _finished = false;

  static const _failure = StorageFailure('Could not save imported covers.');

  @override
  Future<Either<Failure, String>> stage(
    String sourceLeaf,
    Uint8List bytes,
  ) async {
    if (_finished || !isSafeBundleCoverLeaf(sourceLeaf)) return left(_failure);
    try {
      final id = _newId();
      if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return left(_failure);
      // Preserve the format suffix, not the untrusted source basename. Never
      // label arbitrary bundled bytes JPEG or re-encode them as a side effect.
      final suffix = p.extension(sourceLeaf);
      final extension = RegExp(r'^\.[a-zA-Z0-9]{1,8}$').hasMatch(suffix)
          ? suffix
          : '.img';
      final leaf = '$id$extension';
      final reference = '${CoverPaths.prefix}$leaf';
      await Directory(_directory).create(recursive: true);
      final file = File(p.join(_directory, leaf));
      // Dart's exclusive create rejects existing files AND links. Record
      // ownership only after it succeeds, so collision cleanup cannot clobber.
      await file.create(exclusive: true);
      _owned[reference] = file;
      await file.writeAsBytes(bytes, flush: true);
      return right(reference);
    } on Object {
      return left(_failure);
    }
  }

  @override
  Future<Either<Failure, Unit>> retainOnly(Set<String> references) async {
    if (_finished) return left(_failure);
    return _removeExcept(references);
  }

  Future<Either<Failure, Unit>> _removeExcept(Set<String> references) async {
    var failed = false;
    for (final entry in _owned.entries.toList()) {
      if (references.contains(entry.key)) continue;
      try {
        if (entry.value.existsSync()) await entry.value.delete();
        _owned.remove(entry.key);
      } on Object {
        // Continue cleaning other owned files, but report incomplete cleanup.
        failed = true;
      }
    }
    return failed
        ? left(const StorageFailure('Could not clean up imported covers.'))
        : right(unit);
  }

  @override
  Future<Either<Failure, Unit>> rollback() async {
    if (_finished) return right(unit);
    final result = await _removeExcept({});
    if (result.isRight()) _finished = true;
    return result;
  }

  @override
  void commit() {
    _owned.clear();
    _finished = true;
  }
}
