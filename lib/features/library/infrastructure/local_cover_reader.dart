/// Stream-bounded local cover reader with mandatory JPEG sanitization.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/local_cover_reader.dart';

/// Reads covers from `_coversDir`, never from the network.
final class LocalCoverReader {
  /// Creates a reader rooted at the app's active covers directory.
  const LocalCoverReader({required String coversDir}) : _coversDir = coversDir;
  final String _coversDir;

  /// Reads and sanitizes [coverUrl], or returns a typed refusal.
  Future<LocalCoverReadResult> call(String coverUrl) async {
    final leaf = CoverPaths.leafOf(coverUrl);
    if (leaf == null) {
      return const LocalCoverReadFailure(
        LocalCoverReadFailureReason.unsafeReference,
      );
    }
    final file = File(p.join(_coversDir, leaf));
    try {
      if (!file.existsSync()) {
        return const LocalCoverReadFailure(LocalCoverReadFailureReason.missing);
      }
      if (file.lengthSync() > maxLocalCoverSourceBytes) {
        return const LocalCoverReadFailure(
          LocalCoverReadFailureReason.tooLarge,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (builder.length + chunk.length > maxLocalCoverSourceBytes) {
          return const LocalCoverReadFailure(
            LocalCoverReadFailureReason.tooLarge,
          );
        }
        builder.add(chunk);
      }
      final jpeg = await ImageDownscaler.downscaleJpegAsync(
        builder.takeBytes(),
      );
      if (jpeg == null) {
        return const LocalCoverReadFailure(
          LocalCoverReadFailureReason.unreadable,
        );
      }
      return LocalCoverReadSuccess(jpeg);
    } on Exception {
      return const LocalCoverReadFailure(
        LocalCoverReadFailureReason.unreadable,
      );
    }
  }
}

/// Publishing's legacy nullable adapter over the one shared implementation.
Future<List<int>?> Function(String coverUrl) nullableLocalCoverReader(
  String coversDir,
) {
  final reader = LocalCoverReader(coversDir: coversDir);
  return (coverUrl) async => switch (await reader(coverUrl)) {
    LocalCoverReadSuccess(:final bytes) => bytes,
    LocalCoverReadFailure() => null,
  };
}
