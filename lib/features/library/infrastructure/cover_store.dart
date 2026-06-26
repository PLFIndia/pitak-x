/// Local cover file store (infrastructure, AGENTS.md §3.3).
///
/// Writes a captured + downscaled cover to `<coversDir>/<uuid>.jpg` and returns
/// the relative `covers/<uuid>.jpg` reference stored on the book row (the same
/// shape the importer/bundle reader and `BookCover` widget already understand).
/// Pure file IO; the bytes are produced by `ImageDownscaler` before they reach
/// here.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/import_export/infrastructure/cover_paths.dart';
import 'package:uuid/uuid.dart';

/// Persists cover image files under the app covers directory.
final class CoverStore {
  /// Creates a store rooted at [coversDir] (absolute path to `<docs>/covers`).
  CoverStore({required this.coversDir, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  /// Absolute directory where cover files live.
  final String coversDir;
  final Uuid _uuid;

  /// Writes [jpegBytes] to a fresh `covers/<uuid>.jpg` and returns the relative
  /// reference (`covers/<uuid>.jpg`) for the book row. Creates the directory if
  /// needed.
  Future<String> saveJpeg(Uint8List jpegBytes) async {
    Directory(coversDir).createSync(recursive: true);
    final leaf = '${_uuid.v4()}.jpg';
    final file = File(p.join(coversDir, leaf));
    await file.writeAsBytes(jpegBytes, flush: true);
    return '${CoverPaths.prefix}$leaf';
  }
}
