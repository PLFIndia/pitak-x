/// File-backed publish manifest store (infrastructure; Cloudflare plan R5/R9).
///
/// Plain JSON in the app docs dir (public data only: paths, git blob shas,
/// public cover URLs — no token, no credential).
///
/// Two rules changed with schema 2, both deliberate:
///  - **A load that fails is EMPTY, never partial.** The empty record claims no
///    paths, so the next publish reconciles from the remote tree and deletes
///    nothing it cannot prove it wrote (R6). A half-parsed record could claim a
///    path it no longer owns.
///  - **A save is ATOMIC and REPORTED.** The bytes go to a temporary file that
///    is then renamed over the real one, so a crash mid-write leaves either the
///    old record or the new one — never a truncated JSON file that decodes as
///    "nothing is published". And the result is returned: after a commit, a
///    silent save failure would tell the user "published" while the phone has
///    no record of it (R9).
library;

import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
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

  /// Suffix of the file being written. Never read: it only exists between the
  /// write and the rename that publishes it.
  static const String _tempSuffix = '.tmp';

  File get _file => File(p.join(baseDir, _fileName));

  File get _temp => File(p.join(baseDir, '$_fileName$_tempSuffix'));

  /// Fixed, path-free failure message: the store's own error text can contain
  /// a filesystem path (PII) and must not travel as a user-facing sentence.
  static const Failure _saveFailed = StorageFailure(
    'Could not save the publish record.',
  );

  /// Loads the manifest, or [PublishManifest.empty] on any problem.
  ///
  /// Malformed/partial JSON is treated as "no record", never as a smaller
  /// valid one: the reconciliation that follows is safe, guessing is not.
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

  /// Atomically persists [manifest]; a failure is RETURNED, never swallowed.
  @override
  Either<Failure, Unit> save(PublishManifest manifest) {
    try {
      Directory(baseDir).createSync(recursive: true);
      // flush: the bytes reach the filesystem BEFORE the rename publishes the
      // new name, so a power loss can never leave the real path pointing at
      // unwritten data.
      //
      // Same directory ⇒ the rename is atomic on every filesystem Android and
      // iOS ship: the old record is replaced in one step, never truncated.
      _temp
        ..writeAsStringSync(jsonEncode(manifest.toJson()), flush: true)
        ..renameSync(_file.path);
      return right(unit);
    } on Exception {
      // A leftover temp file is deliberately left alone: nothing ever reads
      // it, and the next save overwrites it. Deleting it here would need its
      // own error handling for no gain.
      return left(_saveFailed);
    }
  }
}
