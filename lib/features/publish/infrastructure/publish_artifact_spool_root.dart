/// Hands out and sweeps operation spool folders for Cloudflare publishing.
///
/// Fix-plan L5. Spools used to live under Documents, which is never cleared by
/// the OS and survives "Clear cache", so every killed publish left a full copy
/// of the site behind. They now live in the app's temporary directory, and the
/// next operation sweeps whatever a previous crash left.
///
/// Two rules make the sweep safe:
///
///  1. It only ever deletes a REAL directory whose name is exactly
///     `run-<1..64 of [A-Za-z0-9_-]>` inside the app's own `publish_artifacts`
///     folder. Links, files and any other name are left alone, and a root that
///     is itself a link is not swept at all.
///  2. It never deletes a folder this process is using. The set of live runs
///     is guarded by a lock, so a sweep cannot race a publish that is spooling.
///
/// Cleanup is best-effort by design: a folder that cannot be deleted must never
/// stop a publish (that would be a new dead end).
/// [PublishArtifactSpoolRoot.sweep] still reports the failure as a typed value
/// for callers and tests that care.
library;

import 'dart:async';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';

/// The app-owned spool roots and the run folders currently in use.
final class PublishArtifactSpoolRoot {
  /// Creates the root over the app's temporary directory and, when given, the
  /// legacy Documents directory that older builds spooled into.
  PublishArtifactSpoolRoot({required this.tempRoot, this.legacyRoot});

  /// Folder name used under each root; also the only folder ever swept.
  static const String directoryName = 'publish_artifacts';

  /// The only folder names the sweep may delete.
  static final RegExp runNamePattern = RegExp(r'^run-[A-Za-z0-9_-]{1,64}$');

  /// Where new spools are created (the OS temporary directory).
  final Directory tempRoot;

  /// Where older builds spooled (Documents). Swept, never written to.
  final Directory? legacyRoot;

  static const Failure _createFailed = StorageFailure(
    'Could not prepare the public site files on this device.',
  );
  static const Failure _sweepFailed = StorageFailure(
    'Could not remove old temporary publish files.',
  );

  final Set<String> _inUse = <String>{};
  Future<void> _lock = Future<void>.value();

  /// Creates a fresh, empty `run-` folder after sweeping stale ones.
  ///
  /// The folder is registered as in use until [release] is called, so a later
  /// sweep in this process cannot delete it.
  Future<Either<Failure, Directory>> createRunDirectory() =>
      _serialized(_createRunDirectory);

  /// Forgets a run folder so a later sweep may delete it.
  ///
  /// Safe to call for a folder that was never registered.
  void release(Directory run) {
    _inUse.remove(run.path);
  }

  /// Deletes stale run folders under both roots.
  ///
  /// Returns a typed failure when a folder could not be removed; the folders
  /// that could be removed are gone either way.
  Future<Either<Failure, Unit>> sweep() => _serialized(_sweepAll);

  Future<Either<Failure, Directory>> _createRunDirectory() async {
    // Best-effort: a stale folder that cannot be deleted must not stop a
    // publish. The typed result is available from [sweep] for callers that
    // want to report it.
    await _sweepAll();
    try {
      final root = Directory(p.join(tempRoot.path, directoryName));
      await root.create(recursive: true);
      final run = await root.createTemp('run-');
      _inUse.add(run.path);
      return Right(run);
    } on Exception {
      return const Left(_createFailed);
    }
  }

  Future<Either<Failure, Unit>> _sweepAll() async {
    var failed = false;
    for (final root in _roots()) {
      if (!await _sweepRoot(root)) failed = true;
    }
    return failed ? const Left(_sweepFailed) : right(unit);
  }

  List<Directory> _roots() => [
    Directory(p.join(tempRoot.path, directoryName)),
    if (legacyRoot != null) Directory(p.join(legacyRoot!.path, directoryName)),
  ];

  /// Deletes stale run folders under one root. Returns false on any failure.
  Future<bool> _sweepRoot(Directory root) async {
    // A root that is a link (or a file) is never followed or deleted.
    if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return true;
    }
    var ok = true;
    try {
      // `followLinks: false` yields a Link for a symlink, so a link named
      // `run-x` is skipped instead of deleting its target.
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (!runNamePattern.hasMatch(p.basename(entity.path))) continue;
        if (_inUse.contains(entity.path)) continue;
        try {
          await entity.delete(recursive: true);
        } on Exception {
          ok = false;
        }
      }
    } on Exception {
      ok = false;
    }
    return ok;
  }

  /// Runs [action] with the lock held, so a sweep cannot interleave.
  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _lock;
    final gate = Completer<void>();
    _lock = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }
}
