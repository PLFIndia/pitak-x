/// File-backed publish manifest store (infrastructure, #32).
///
/// Port of Kotlin `PublishManifestStore`. Plain JSON in the app docs dir
/// (public data only). All failures degrade to [PublishManifest.empty] — a
/// full, correct publish — never a crash. The manifest is an optimization, not
/// a correctness input.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/domain/publish_manifest.dart';

/// Reads/writes the publish manifest at `<baseDir>/publish_manifest.json`.
final class FilePublishManifestStore implements PublishManifestGateway {
  /// Creates the store rooted at [baseDir] (typically the app docs dir).
  const FilePublishManifestStore({required this.baseDir});

  /// Directory holding the manifest.
  final String baseDir;

  static const String _fileName = 'publish_manifest.json';

  File get _file => File(p.join(baseDir, _fileName));

  /// Loads the manifest, or [PublishManifest.empty] on any problem.
  @override
  PublishManifest load() {
    try {
      final f = _file;
      if (!f.existsSync()) return PublishManifest.empty;
      final json = jsonDecode(f.readAsStringSync());
      if (json is! Map<String, dynamic>) return PublishManifest.empty;
      return PublishManifest.fromJson(json);
    } on Exception {
      return PublishManifest.empty;
    }
  }

  /// Persists [manifest]. Best-effort: a failed write just means the next
  /// publish does more work.
  @override
  void save(PublishManifest manifest) {
    try {
      Directory(baseDir).createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(manifest.toJson()), flush: true);
    } on Exception {
      // Ignore — manifest is a cache, not a source of truth.
    }
  }

  /// Clears the manifest (e.g. on sign-out). Idempotent.
  void clear() {
    try {
      final f = _file;
      if (f.existsSync()) f.deleteSync();
    } on Exception {
      // Best-effort.
    }
  }
}
