/// Atomic file-backed Cloudflare publish record (infrastructure; R5/R9/L4).
///
/// The JSON contains only public asset/target metadata. A corrupt load becomes
/// the empty record, never a partial ownership claim. Saves use a temp file in
/// the same directory, flush, and rename so a crash leaves either old or new
/// state.
///
/// There is a SECOND record next to the live one: the deploy this phone
/// attempted but has not recorded as landed. It is written immediately before
/// the PUT, because the new publish id exists only in that request. A lost
/// response then leaves a record the next preflight can recognise, instead of
/// a site that looks foreign (fix-plan L4).
library;

import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';

/// Stores `<baseDir>/cloudflare_publish_manifest.json` and its pending attempt.
final class FileCloudflareManifestStore implements CloudflareManifestStore {
  /// Creates the store rooted at the app documents directory.
  const FileCloudflareManifestStore({required this.baseDir});

  /// Directory containing the public publish record.
  final String baseDir;

  static const String _fileName = 'cloudflare_publish_manifest.json';
  static const String _pendingName = 'cloudflare_publish_pending.json';
  static const String _tempSuffix = '.tmp';
  static const Failure _saveFailed = StorageFailure(
    'Could not save the Cloudflare publish record.',
  );

  File get _file => File(p.join(baseDir, _fileName));
  File get _pending => File(p.join(baseDir, _pendingName));

  @override
  CloudflareSiteManifest load() => _load(_file);

  @override
  CloudflareSiteManifest loadPending() => _load(_pending);

  @override
  Either<Failure, Unit> save(CloudflareSiteManifest manifest) =>
      _write(_file, manifest);

  @override
  Either<Failure, Unit> savePending(CloudflareSiteManifest manifest) =>
      _write(_pending, manifest);

  @override
  Either<Failure, Unit> clearPending() {
    try {
      final file = _pending;
      if (file.existsSync()) file.deleteSync();
      return right(unit);
    } on Exception {
      return left(_saveFailed);
    }
  }

  CloudflareSiteManifest _load(File file) {
    try {
      if (!file.existsSync()) return CloudflareSiteManifest.empty;
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic>
          ? CloudflareSiteManifest.fromJson(decoded)
          : CloudflareSiteManifest.empty;
    } on Exception {
      return CloudflareSiteManifest.empty;
    }
  }

  Either<Failure, Unit> _write(File file, CloudflareSiteManifest manifest) {
    try {
      Directory(baseDir).createSync(recursive: true);
      File('${file.path}$_tempSuffix')
        ..writeAsStringSync(jsonEncode(manifest.toJson()), flush: true)
        ..renameSync(file.path);
      return right(unit);
    } on Exception {
      // A leftover temp file is never read and is overwritten by the next save.
      // Filesystem detail (which may include a private path) stays out of UI.
      return left(_saveFailed);
    }
  }
}
