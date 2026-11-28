/// Measures how much room the library takes on disk (backup
/// infrastructure, backup rework BR9).
///
/// WHY THIS FILE EXISTS (beginner note): the notice before a backup and
/// before a restore says how much free storage the run needs, and that
/// follows from the size of the library (`resource_notice.dart`). This file
/// adds up the sizes of the library's files. It only LOOKS: it opens no
/// file and writes nothing. (It names the covers folder, so
/// `cover_files_immutable_test.dart` lists it as a reader and checks that
/// it never writes.)
///
/// What is counted, in the folder of the data generation in use:
///
/// ```text
/// pitaka.db, pitaka.db-wal, …   the catalogue and SQLite's side files
/// covers/<every file>           the cover pictures
/// every other file              the borrowers vault (its database, its
///                               key blobs) and one empty marker file
/// ```
///
/// Where the work runs: a library can have 10,000 cover pictures, and
/// asking for the size of each takes a moment. So the adding up happens in
/// a one-shot worker isolate, and the screen keeps moving.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/domain/library_footprint.dart';

/// What the worker needs, as plain text (only plain data may be sent to an
/// isolate): the generation's folder, the name of the catalogue database
/// in it, and the covers folder.
typedef LibraryFootprintJob = ({
  String generationDir,
  String catalogueDbName,
  String coversDir,
});

/// [LibraryFootprintSource] over the files of the data generation in use.
final class FileLibraryFootprintSource implements LibraryFootprintSource {
  /// Creates the source. [activeGeneration] resolves the generation in use
  /// at the moment of each read (a restore switches generations).
  const FileLibraryFootprintSource({required this.activeGeneration});

  /// Resolves the data generation in use.
  final Future<DataGeneration> Function() activeGeneration;

  @override
  Future<LibraryFootprint?> read() async {
    try {
      final generation = await activeGeneration();
      return await _measureInWorker((
        generationDir: generation.path,
        catalogueDbName: p.basename(generation.catalogueDbPath),
        coversDir: generation.coversDir,
      ));
    } on Object {
      // Deliberately not rethrown and not logged (a path could be in the
      // text): "could not be read" is a normal answer of this port, and
      // the notice says so. Nothing depends on these sizes but a sentence.
      return null;
    }
  }

  /// Starts the worker for [job] and waits for its answer.
  ///
  /// A function of its own ON PURPOSE (beginner note): the little function
  /// handed to `Isolate.run` is copied to the other isolate together with
  /// every variable it can see. Here it can see [job] and nothing else.
  static Future<LibraryFootprint> _measureInWorker(LibraryFootprintJob job) =>
      Isolate.run(
        () => measureLibraryFootprint(job),
        debugName: 'pitaka-library-footprint',
      );
}

/// The work of the worker: adds up the file sizes [job] describes.
/// Synchronous; the app calls it through [FileLibraryFootprintSource].
///
/// Throws a `FileSystemException` when the generation's folder cannot be
/// listed. A covers folder that does not exist counts as empty (a library
/// without cover pictures has none). A single file that disappears between
/// the listing and the look at its size counts as 0: the sum is an
/// estimate, and a cover deleted this very moment must not make it
/// "unknown".
LibraryFootprint measureLibraryFootprint(LibraryFootprintJob job) {
  var catalogueBytes = 0;
  var vaultBytes = 0;
  final root = Directory(job.generationDir);
  for (final file in root.listSync(followLinks: false).whereType<File>()) {
    final bytes = _lengthOf(file);
    // SQLite's side files carry the database's name in front
    // (`pitaka.db-wal`), so one test finds them all.
    if (p.basename(file.path).startsWith(job.catalogueDbName)) {
      catalogueBytes += bytes;
    } else {
      vaultBytes += bytes;
    }
  }

  var coverBytes = 0;
  final covers = Directory(job.coversDir);
  if (covers.existsSync()) {
    for (final file in covers.listSync(followLinks: false).whereType<File>()) {
      coverBytes += _lengthOf(file);
    }
  }
  return LibraryFootprint(
    catalogueBytes: catalogueBytes,
    coverBytes: coverBytes,
    vaultBytes: vaultBytes,
  );
}

/// The size of [file], or 0 when it is gone by now.
int _lengthOf(File file) {
  try {
    return file.lengthSync();
  } on FileSystemException {
    return 0;
  }
}
