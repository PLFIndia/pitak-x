/// File-backed, operation-scoped spool for GitHub publish artifacts (review
/// finding 6).
///
/// What it does (beginner note): the section builder hands each finished file
/// here and keeps only path/sha/size metadata. The commit later asks for one
/// path at a time, gets its bytes back, and sends them — so a 1,000-cover
/// site never sits in memory as one list of byte arrays.
///
/// Safety rules:
///  - only a safe site path is accepted (`SitePath.tryParse`), and only when
///    the declared sha really is the sha of those bytes;
///  - the file's leaf name IS its git blob sha (lower-case hex), so no user
///    text ever becomes a path, and identical content is stored once;
///  - `read` re-hashes the bytes before returning them, so a damaged or
///    replaced temp file can never be committed as this content;
///  - `dispose` removes only this operation's run folder through
///    [PublishArtifactSpoolRoot], which also sweeps what a killed publish
///    left behind (fix-plan L5).
library;

import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_artifact_store.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';

/// A lazily created temporary artifact spool handed out by [spoolRoot].
final class FileGitHubArtifactStore implements GitHubArtifactStore {
  /// Creates an empty operation spool. The directory appears on first write.
  FileGitHubArtifactStore({required this.spoolRoot});

  /// Owns the roots, the sweep and the set of live run folders.
  final PublishArtifactSpoolRoot spoolRoot;

  static const Failure _invalid = ValidationFailure(
    'The site files could not be prepared safely.',
  );
  static const Failure _ioFailed = StorageFailure(
    'Could not prepare the public site files on this device.',
  );

  final Map<String, _SpooledArtifact> _byPath = {};
  Directory? _directory;

  @override
  Future<Either<Failure, Unit>> write(PublishFile file) async {
    final path = SitePath.tryParse(file.path);
    if (path == null ||
        file.gitSha.isEmpty ||
        GitBlobSha.of(file.bytes) != file.gitSha) {
      return const Left(_invalid);
    }
    try {
      final existing = _directory;
      final Directory directory;
      if (existing != null) {
        directory = existing;
      } else {
        final created = await spoolRoot.createRunDirectory();
        final run = created.toNullable();
        if (run == null) return Left(created.swap().toNullable()!);
        _directory = directory = run;
      }
      // The leaf is the content sha: a safe, lower-case hex name that also
      // makes identical content share one file (two covers with the same
      // bytes are written once).
      final leaf = file.gitSha.toLowerCase();
      final output = File(p.join(directory.path, leaf));
      if (!output.existsSync()) {
        final sink = output.openWrite();
        try {
          sink.add(file.bytes);
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      _byPath[file.path] = _SpooledArtifact(
        leaf: leaf,
        size: file.size,
        gitSha: file.gitSha,
      );
      return right(unit);
    } on Exception {
      return const Left(_ioFailed);
    }
  }

  @override
  Future<List<int>?> read(String path) async {
    final artifact = _byPath[path];
    final directory = _directory;
    if (artifact == null || directory == null) return null;
    try {
      final bytes = await File(
        p.join(directory.path, artifact.leaf),
      ).readAsBytes();
      // Verify before handing the bytes on: the commit must send exactly the
      // content the snapshot described, never whatever is on disk now.
      if (bytes.length != artifact.size) return null;
      return GitBlobSha.of(bytes) == artifact.gitSha ? bytes : null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    final directory = _directory;
    _directory = null;
    _byPath.clear();
    if (directory == null) return;
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on Exception {
      // Best effort: the spool root releases the folder below, so a later
      // sweep can retry it and the failed delete changes no result.
    } finally {
      spoolRoot.release(directory);
    }
  }
}

/// One spooled file: its content-addressed leaf, exact size and sha.
final class _SpooledArtifact {
  const _SpooledArtifact({
    required this.leaf,
    required this.size,
    required this.gitSha,
  });

  final String leaf;
  final int size;
  final String gitSha;
}
