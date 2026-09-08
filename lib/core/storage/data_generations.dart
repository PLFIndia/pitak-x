/// Versioned on-device data generations (M02, astra-review.md).
///
/// Why this exists (beginner note): a restore replaces THREE things that only
/// make sense together — the catalogue database, the encrypted borrowers vault
/// (DB + wrapped key), and the cover images. Before M02 each was swapped in
/// place, one after another, so a crash or IO error between two of them left
/// the device on a mix of old and new data with nothing to detect it.
///
/// The fix is the pattern LevelDB uses for its `CURRENT` → `MANIFEST-N`
/// pointer (`db/filename.cc` `SetCurrentFile`, BSD-3-Clause, read 2026-09-08):
///
/// ```text
/// <docs>/data/CURRENT            one line: the active generation's name
/// <docs>/data/gen-000001/        a COMPLETE data set (catalogue + vault + covers)
/// <docs>/data/gen-000002/        the next one, being built by a restore
/// ```
///
/// A restore writes a whole new generation directory, marks it `COMPLETE`
/// (flushed, written last), and then swaps ONE small file: `CURRENT.tmp` is
/// written + flushed and renamed over `CURRENT`. `rename(2)` replaces the
/// target atomically, so the pointer always names either the old or the new
/// generation — never half of each. Anything that fails before the rename
/// simply leaves the builder directory to be discarded; the live data is
/// untouched. Startup recovery is LevelDB's rule too: obey the pointer only if
/// it names a complete generation, otherwise fall back to the newest complete
/// one, and delete every other `gen-*` directory (so a crashed restore never
/// leaves a second plaintext copy of the catalogue behind — privacy §3.1).
///
/// Honest limits (recorded, not hidden):
///  - `dart:io` cannot `fsync` a directory, so the durability of the rename
///    itself relies on the filesystem committing directory metadata in order
///    (ext4 / f2fs on Android do). File CONTENTS are flushed before the rename.
///  - Android is the only shipping target (M18). POSIX lets us delete the old
///    generation while a closing SQLite handle still has it open; on Windows
///    that delete would fail (and is reported, not swallowed).
///
/// This type is pure file IO: no crypto, no secrets, no database knowledge.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Sub-directory of the docs dir that holds every generation + the pointer.
const String _dataDirName = 'data';

/// Pointer file naming the active generation (LevelDB: `CURRENT`).
const String _currentFileName = 'CURRENT';

/// Marker written LAST into a generation; its presence means "every file in
/// this directory is finished". A generation without it is never used.
const String _completeMarkerName = 'COMPLETE';

/// Generation directory name prefix + zero-padded width (`gen-000001`).
const String _generationPrefix = 'gen-';
const int _generationDigits = 6;

/// Filenames restore owns. On first launch after M02 they are moved from the
/// flat docs dir into `gen-000001`; everything else (events, posters, publish
/// manifest, scratch dirs) stays where it was because backups never contain it.
const String _catalogueDbName = 'pitaka.db';
const String _coversDirName = 'covers';
const List<String> _vaultFileNames = [
  'borrowers.db',
  'vault_backup_blob',
  'vault_biometric_blob',
];

/// SQLite side files that must travel with their database (a hot `-journal`
/// after a crash is part of the database's state, not garbage).
const List<String> _sqliteCompanionSuffixes = ['-journal', '-wal', '-shm'];

/// One generation directory and the well-known paths inside it.
///
/// Immutable value: holding a [DataGeneration] does not keep it alive — the
/// store may delete it after a switch. Providers re-resolve on every change.
final class DataGeneration {
  const DataGeneration._({required this.name, required this.path});

  /// Directory leaf name, e.g. `gen-000001`. Sorts chronologically.
  final String name;

  /// Absolute directory path.
  final String path;

  /// Absolute path of the plain catalogue database (books + wishlist).
  String get catalogueDbPath => p.join(path, _catalogueDbName);

  /// Absolute path of the cover-image directory.
  String get coversDir => p.join(path, _coversDirName);

  /// Directory holding the vault artifacts (`borrowers.db`, key blobs). The
  /// vault store is rooted here instead of at the docs dir.
  String get vaultDir => path;

  @override
  String toString() => 'DataGeneration($name)';
}

/// Owns `<docs>/data`: adoption of the legacy flat layout, startup recovery,
/// building the next generation, and the atomic pointer switch.
final class DataGenerations {
  /// Creates a store over the app documents directory [docsDir].
  const DataGenerations({required this.docsDir});

  /// The app documents directory (parent of `data/`).
  final String docsDir;

  String get _dataDir => p.join(docsDir, _dataDirName);
  String get _currentPath => p.join(_dataDir, _currentFileName);

  /// Resolves the active generation, repairing after any crash on the way.
  ///
  /// Steps, in order:
  ///  1. first launch after M02: move the flat-layout artifacts into
  ///     `gen-000001` (idempotent — a crash half-way is simply finished on the
  ///     next call; an existing destination file is never overwritten);
  ///  2. read `CURRENT`; accept it only if it names a COMPLETE generation
  ///     inside `data/`; otherwise fall back to the newest complete one;
  ///  3. if nothing complete exists, create an empty `gen-000001`;
  ///  4. make `CURRENT` name the chosen generation (no-op when already so);
  ///  5. delete every OTHER `gen-*` directory (crashed builders, superseded
  ///     generations). Nothing outside `gen-*` is ever touched.
  ///
  /// Throws [FileSystemException] when the docs dir itself is unusable; the
  /// app cannot run without its data directory, so there is nothing safe to
  /// fall back to.
  DataGeneration open() {
    Directory(_dataDir).createSync(recursive: true);
    if (!File(_currentPath).existsSync()) _adoptFlatLayout();

    var active = _readPointer();
    active ??= _newestComplete();
    if (active == null) {
      final fresh = _generation(_firstFreeNumber());
      Directory(fresh.path).createSync(recursive: true);
      complete(fresh);
      active = fresh;
    }
    if (_readPointerRaw() != active.name) _writePointer(active.name);
    _deleteAllExcept(active.name);
    return active;
  }

  /// Creates the next, empty generation directory (name sorts after
  /// [active] and after every leftover). It is NOT complete and NOT active:
  /// the caller fills it, then calls [complete] and [activate], or [discard].
  DataGeneration beginNext(DataGeneration active) {
    final next = _generation(_firstFreeNumber(atLeast: _numberOf(active) + 1));
    Directory(next.path).createSync(recursive: true);
    return next;
  }

  /// Marks [generation] as fully written. Call ONLY after every file in it has
  /// been written and flushed — the marker's existence is the promise startup
  /// recovery relies on.
  void complete(DataGeneration generation) {
    File(
      p.join(generation.path, _completeMarkerName),
    ).writeAsBytesSync(const [], flush: true);
  }

  /// Atomically makes [generation] the active one and deletes the previous
  /// generation(s). The switch is a single `rename` of the pointer file.
  ///
  /// Throws [StateError] if [generation] is not [complete]d (so an unfinished
  /// build can never become live), and rethrows [FileSystemException] from the
  /// pointer write/rename with the temp pointer removed and the OLD generation
  /// still active (nothing is deleted before the rename succeeds).
  DataGeneration activate(DataGeneration generation) {
    if (!_isComplete(generation.name)) {
      throw StateError(
        '${generation.name} is not complete; refusing to activate',
      );
    }
    _writePointer(generation.name);
    _deleteAllExcept(generation.name);
    return generation;
  }

  /// Deletes an abandoned builder directory. Idempotent. Refuses (throws
  /// [StateError]) to delete the generation `CURRENT` names — live data is
  /// only ever removed by [activate] after a successful switch.
  void discard(DataGeneration generation) {
    if (_readPointerRaw() == generation.name) {
      throw StateError('${generation.name} is active; refusing to discard');
    }
    final dir = Directory(generation.path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  // --- adoption -----------------------------------------------------------

  /// Moves the pre-M02 flat files into `gen-000001` without ever overwriting
  /// a file that already sits inside the generation (a previous, interrupted
  /// adoption wins; the leftover stays visible rather than being clobbered).
  void _adoptFlatLayout() {
    final flatLeaves = <String>[
      _catalogueDbName,
      ..._sqliteCompanionSuffixes.map((s) => '$_catalogueDbName$s'),
      ..._vaultFileNames,
      ..._sqliteCompanionSuffixes.map((s) => '${_vaultFileNames.first}$s'),
    ];
    final flatCovers = Directory(p.join(docsDir, _coversDirName));
    final anythingToAdopt =
        flatLeaves.any((leaf) => File(p.join(docsDir, leaf)).existsSync()) ||
        flatCovers.existsSync() ||
        Directory(_generationPath(1)).existsSync();
    if (!anythingToAdopt) return;

    final target = _generation(1);
    Directory(target.path).createSync(recursive: true);
    for (final leaf in flatLeaves) {
      final source = File(p.join(docsDir, leaf));
      if (!source.existsSync()) continue;
      final destination = File(p.join(target.path, leaf));
      if (destination.existsSync()) continue; // never overwrite; see doc
      source.renameSync(destination.path);
    }
    if (flatCovers.existsSync()) {
      final destination = Directory(target.coversDir);
      if (!destination.existsSync()) {
        flatCovers.renameSync(destination.path);
      } else {
        // Both exist (crash between moving files): merge file-by-file, again
        // never overwriting, then drop the flat dir only once it is empty.
        for (final entity in flatCovers.listSync()) {
          if (entity is! File) continue;
          final moved = File(p.join(destination.path, p.basename(entity.path)));
          if (moved.existsSync()) continue;
          entity.renameSync(moved.path);
        }
        if (flatCovers.listSync().isEmpty) flatCovers.deleteSync();
      }
    }
    complete(target);
  }

  // --- pointer ------------------------------------------------------------

  /// The trimmed pointer contents, or null when absent/unreadable. Does NOT
  /// validate the target; see [_readPointer].
  String? _readPointerRaw() {
    final file = File(_currentPath);
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  /// The generation the pointer names, or null when the pointer is absent,
  /// malformed, points outside `data/`, or names an incomplete generation.
  DataGeneration? _readPointer() {
    final name = _readPointerRaw();
    if (name == null || !_isGenerationName(name)) return null;
    if (!_isComplete(name)) return null;
    return _generationNamed(name);
  }

  /// Write-temp-then-rename (LevelDB `SetCurrentFile`; SQLite's durability
  /// pattern). The live pointer is always either the old or the new value.
  void _writePointer(String name) {
    final tmp = File('$_currentPath.tmp');
    try {
      tmp
        ..writeAsStringSync('$name\n', flush: true)
        ..renameSync(_currentPath);
    } on FileSystemException {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
  }

  // --- generation bookkeeping --------------------------------------------

  DataGeneration _generation(int number) => _generationNamed(
    '$_generationPrefix${number.toString().padLeft(_generationDigits, '0')}',
  );

  DataGeneration _generationNamed(String name) =>
      DataGeneration._(name: name, path: p.join(_dataDir, name));

  String _generationPath(int number) => _generation(number).path;

  /// Strictly `gen-` + exactly six digits: anything else (traversal, garbage,
  /// a hand-edited pointer) is not a generation and is never followed.
  static final RegExp _generationPattern = RegExp(
    '^$_generationPrefix\\d{$_generationDigits}\$',
  );

  bool _isGenerationName(String name) => _generationPattern.hasMatch(name);

  int _numberOf(DataGeneration generation) =>
      int.parse(generation.name.substring(_generationPrefix.length));

  bool _isComplete(String name) =>
      Directory(p.join(_dataDir, name)).existsSync() &&
      File(p.join(_dataDir, name, _completeMarkerName)).existsSync();

  /// Every `gen-*` directory currently on disk, complete or not.
  List<String> _generationNames() {
    final dir = Directory(_dataDir);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .where(_isGenerationName)
        .toList()
      ..sort();
  }

  DataGeneration? _newestComplete() {
    final names = _generationNames().where(_isComplete).toList();
    if (names.isEmpty) return null;
    return _generationNamed(names.last);
  }

  /// Smallest number ≥ [atLeast] whose directory does not exist — leftovers
  /// are skipped, never reused, so a builder always starts empty.
  int _firstFreeNumber({int atLeast = 1}) {
    var number = atLeast;
    while (Directory(_generationPath(number)).existsSync()) {
      number++;
    }
    return number;
  }

  /// Removes every `gen-*` directory except [keep]. Only generation-named
  /// directories directly under `data/` qualify; nothing else is touched.
  void _deleteAllExcept(String keep) {
    for (final name in _generationNames()) {
      if (name == keep) continue;
      Directory(p.join(_dataDir, name)).deleteSync(recursive: true);
    }
  }
}
