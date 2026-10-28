/// Atomic file-backed Cloudflare publish record (infrastructure; R5/R9).
///
/// The JSON contains only public asset/target metadata. A corrupt load becomes
/// the empty record, never a partial ownership claim. Saves use a temp file in
/// the same directory, flush, and rename so a crash leaves either old or new
/// state.
library;

import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';

/// Stores `<baseDir>/cloudflare_publish_manifest.json`.
final class FileCloudflareManifestStore implements CloudflareManifestStore {
  /// Creates the store rooted at the app documents directory.
  const FileCloudflareManifestStore({required this.baseDir});

  /// Directory containing the public publish record.
  final String baseDir;

  static const String _fileName = 'cloudflare_publish_manifest.json';
  static const String _tempName = '$_fileName.tmp';
  static const Failure _saveFailed = StorageFailure(
    'Could not save the Cloudflare publish record.',
  );

  File get _file => File(p.join(baseDir, _fileName));
  File get _temp => File(p.join(baseDir, _tempName));

  @override
  CloudflareSiteManifest load() {
    try {
      final file = _file;
      if (!file.existsSync()) return CloudflareSiteManifest.empty;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        return CloudflareSiteManifest.empty;
      }
      return CloudflareSiteManifest.fromJson(decoded);
    } on Exception {
      return CloudflareSiteManifest.empty;
    }
  }

  @override
  Either<Failure, Unit> save(CloudflareSiteManifest manifest) {
    try {
      Directory(baseDir).createSync(recursive: true);
      _temp
        ..writeAsStringSync(jsonEncode(manifest.toJson()), flush: true)
        ..renameSync(_file.path);
      return right(unit);
    } on Exception {
      // A leftover temp file is never read and is overwritten by the next save.
      // Filesystem detail (which may include a private path) stays out of UI.
      return left(_saveFailed);
    }
  }
}
