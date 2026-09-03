/// Port for the local cover-image files (domain, AGENTS.md §3.3).
///
/// Declared in `domain` so application code (cover controller, logo
/// controller, the orphan janitor) depends on this contract rather than on
/// the file-IO implementation (`infrastructure/cover_store.dart`). It knows
/// nothing about how images are produced — bytes in, reference out.
library;

import 'dart:typed_data';

/// Reads/writes/deletes cover image files under the app's covers directory.
abstract interface class CoverFiles {
  /// Writes [jpegBytes] to a fresh file and returns its relative reference
  /// (`covers/<uuid>.jpg`) for the book row / logo setting.
  Future<String> saveJpeg(Uint8List jpegBytes);

  /// Deletes the file behind a local reference (`covers/<leaf>` or legacy
  /// `file://…/<leaf>`). Remote/blank/unsafe references and missing files are
  /// a no-op. Never reaches outside the covers directory.
  Future<void> deleteFile(String? coverRef);

  /// Leaf file names currently present in the covers directory.
  List<String> listLeaves();
}
