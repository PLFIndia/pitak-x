// A check done BY HAND, not by CI: how much memory does READING a large
// backup need? (Backup rework BR5; review finding P3-B3; safety-check point
// SC9.)
//
// WHY THIS EXISTS (beginner note): the app's first ZIP reader holds the whole
// archive and everything in it in memory. BR5 adds a reader that works from
// the file and takes one entry at a time (`BoundedZipFile`). This script
// drives that REAL reader on a large made-up backup while the Dart heap is
// capped. If the reader went back to holding an entry, or the archive, in
// memory, the run would stop with "Out of Memory" instead of printing its
// numbers.
//
// What it does, in a temporary folder that it removes again:
//  1. makes a file in place of a large `books.db` (pages like a database's,
//     so it shrinks when packed, as a real one does);
//  2. packs a backup with the app's own packer (`packBackupZip`): a small
//     manifest, that database (deflated, from a file), and cover pictures
//     of random bytes (stored: like JPEG they do not shrink);
//  3. starts ITSELF a second time to do the reading, so that the memory
//     figure of the reading is not hidden behind that of the packing. The
//     second run opens the backup with the reader under the rules a
//     restore will use, writes every entry to a file, and compares: every
//     size, the database by checksum, and every 97th picture byte for
//     byte.
//
// How to run it (from the repository root). Compile first: under plain
// `dart run` the compiler itself needs several hundred megabytes, which
// hides what the reader needs.
//
//   dart compile exe tool/zip_reader_memory_check.dart -o /tmp/zip_reader_memory_check
//   DART_VM_OPTIONS=--old_gen_heap_size=32 /tmp/zip_reader_memory_check
//
// A SECOND MODE (backup rework BR6): with `--restore` as the first argument
// the reading is done the way a restore does it since BR6, by the two
// steps its worker isolates run: `readRestoreArchive` (the manifest into
// memory, the database into a work folder, the covers only listed) and
// `buildRestoredCovers` (every listed cover straight into a covers
// folder). Before them it runs the inspection the Restore page asks for
// when a file is picked, and counts what that unpacks: the manifest
// alone. Same made-up backup, same heap cap, same comparison:
//
//   DART_VM_OPTIONS=--old_gen_heap_size=32 /tmp/zip_reader_memory_check --restore
//
// Optional arguments after that, in this order: the number of covers
// (default 10000), the size of one cover in bytes (default 107000, which
// makes about 1 GiB of covers), the size of the database in MiB (default
// 200).
//
// It needs free disk space of about twice the backup plus the database
// (2.7 GB with the defaults). It runs on a computer, not on a phone: the
// memory figure of a phone comes from the device runs of BR10.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/backup_preflight.dart';
import 'package:pitaka/features/backup/infrastructure/backup_zip_file.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/import_export/domain/zip_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/bounded_zip_file.dart';

const int _mebibyte = 1024 * 1024;

String _megabytes(int bytes) => '${(bytes / _mebibyte).toStringAsFixed(1)} MB';

/// The picture with the number [index]: always the same bytes for the same
/// number, so it can be made once for packing and again for comparing.
Uint8List _picture(int index, int length) {
  final random = Random(index);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// The file name of the picture with the number [index].
String _coverLeaf(int index) => 'c${index.toString().padLeft(6, '0')}.jpg';

String _coverName(int index) => 'cover_${_coverLeaf(index)}';

/// The checksum of the file at [path], read in pieces.
int _crcOfFile(String path) {
  final file = File(path).openSync();
  try {
    final piece = Uint8List(_mebibyte);
    var crc = 0;
    while (true) {
      final read = file.readIntoSync(piece);
      if (read <= 0) return crc;
      crc = getCrc32(Uint8List.sublistView(piece, 0, read), crc);
    }
  } finally {
    file.closeSync();
  }
}

/// The limits of the made-up backup. These are NOT the app's limits; the
/// limits themselves are tested in the reader's and the writer's tests.
BackupLimits _limitsFor(int coverCount, int coverBytes, int databaseBytes) =>
    BackupLimits(
      maxCovers: max(coverCount, 1),
      maxContentBytes: 4 * 1024 * _mebibyte - 1,
      maxCoverBytes: max(coverBytes, 1),
      maxDatabaseBytes: max(databaseBytes, 1),
      maxTextEntryBytes: 4 * _mebibyte,
    );

/// A manifest a restore can use: it announces the database and the covers
/// this backup holds, and nothing else.
const String _manifestText =
    '{"schemaVersion":1,"exportedAt":0,"hasBooks":true,"hasWishlist":false,'
    '"hasBorrowers":false,"hasBackupBlob":false,"hasCovers":true}';
const String _readPhase = '--read-phase';
const String _restorePhase = '--restore-phase';
const String _restoreMode = '--restore';

void main(List<String> arguments) {
  if (arguments.isNotEmpty &&
      (arguments.first == _readPhase || arguments.first == _restorePhase)) {
    final phase = arguments.first == _readPhase ? _read : _restoreSteps;
    phase(
      root: arguments[1],
      coverCount: int.parse(arguments[2]),
      coverBytes: int.parse(arguments[3]),
      databaseBytes: int.parse(arguments[4]),
      databaseCrc: int.parse(arguments[5]),
    );
    return;
  }
  final asRestore = arguments.isNotEmpty && arguments.first == _restoreMode;
  final numbers = asRestore ? arguments.sublist(1) : arguments;
  final coverCount = numbers.isNotEmpty ? int.parse(numbers[0]) : 10000;
  final coverBytes = numbers.length > 1 ? int.parse(numbers[1]) : 107000;
  final databaseMebibytes = numbers.length > 2 ? int.parse(numbers[2]) : 200;

  final root = Directory.systemTemp.createTempSync('zip_reader_memory_check_');
  try {
    // 1. The stand-in for a large database, written in pieces so that
    //    making the test data needs little memory too.
    final databasePath = '${root.path}/source.db';
    final random = Random(7);
    final page = Uint8List(4096);
    final databaseFile = File(databasePath).openSync(mode: FileMode.write);
    for (var i = 0; i < databaseMebibytes * 256; i++) {
      for (var j = 0; j < page.length; j++) {
        page[j] = j < 100
            ? (j * 7) & 0xFF
            : j < 3000
            ? 0x20 + random.nextInt(40)
            : 0;
      }
      databaseFile.writeFromSync(page);
    }
    databaseFile.closeSync();
    final databaseBytes = databaseMebibytes * _mebibyte;
    final databaseCrc = _crcOfFile(databasePath);
    final limits = _limitsFor(coverCount, coverBytes, databaseBytes);

    // 2. The backup, packed by the app's own packer.
    final manifest = Uint8List.fromList(_manifestText.codeUnits);
    stdout.writeln(
      'Packing $coverCount covers of $coverBytes bytes and a '
      '${_megabytes(databaseBytes)} database...',
    );
    final packed = packBackupZip(
      entries: [
        PlannedBackupEntry('manifest.json', manifest.length, () => manifest),
        PlannedBackupEntry.streamed('books.db', databaseBytes, databasePath),
        for (var i = 0; i < coverCount; i++)
          PlannedBackupEntry(
            _coverName(i),
            coverBytes,
            () => _picture(i, coverBytes),
          ),
      ],
      partPath: '${root.path}/backup.part',
      finalPath: '${root.path}/backup.pitabak',
      maxArchiveBytes: limits.maxArchiveBytes,
    );
    if (!packed.inPlace) {
      stderr.writeln('The made-up backup is larger than its own limits.');
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'The backup is ${_megabytes(packed.sizeBytes)} (peak memory of the '
      'packing: ${_megabytes(ProcessInfo.maxRss)}). Reading it in a run of '
      'its own...',
    );

    // 3. The reading, in a second run of this very program. It gets the
    //    same heap cap: `DART_VM_OPTIONS` is handed down with the rest of
    //    the environment. Under `dart run` the program is the Dart VM and
    //    the script has to be named again.
    final script = Platform.script.toFilePath();
    final reading = Process.runSync(Platform.resolvedExecutable, [
      if (script.endsWith('.dart')) script,
      if (asRestore) _restorePhase else _readPhase,
      root.path,
      '$coverCount',
      '$coverBytes',
      '$databaseBytes',
      '$databaseCrc',
    ]);
    stdout.write(reading.stdout);
    stderr.write(reading.stderr);
    exitCode = reading.exitCode;
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// The second run: reads the backup under `root` with the real reader.
void _read({
  required String root,
  required int coverCount,
  required int coverBytes,
  required int databaseBytes,
  required int databaseCrc,
}) {
  final limits = _limitsFor(coverCount, coverBytes, databaseBytes);
  final out = Directory('$root/out')..createSync();
  var problems = 0;
  void problem(String what) {
    problems++;
    stderr.writeln('WRONG: $what');
  }

  // The reader, as a restore will use it.
  final openClock = Stopwatch()..start();
  final file = BoundedZipFile.open(
    '$root/backup.pitabak',
    limits: ZipLimits.forBackup(limits),
    policy: (name) => backupEntryRule(name, limits),
  );
  openClock.stop();
  final names = [for (final entry in file.entries) entry.name];
  final takeClock = Stopwatch()..start();
  try {
    if (names.length != coverCount + 2) {
      problem('${names.length} entries, not ${coverCount + 2}');
    }
    for (var i = 0; i < file.entries.length; i++) {
      final entry = file.entries[i];
      if (entry.verdict != ZipEntryVerdict.take) {
        problem('${entry.name} is ${entry.verdict.name}');
        continue;
      }
      if (entry.name == 'manifest.json') {
        final content = file.read(entry, maxBytes: limits.maxTextEntryBytes);
        if (String.fromCharCodes(content) != _manifestText) {
          problem('the manifest has another content');
        }
        continue;
      }
      final target = '${out.path}/$i';
      file.writeTo(entry, target);
      final written = File(target).lengthSync();
      if (written != entry.size) {
        problem('${entry.name}: $written bytes on disk, ${entry.size} said');
      }
    }
  } finally {
    file.close();
  }
  takeClock.stop();
  // Taken HERE: the comparing below reads whole pictures into memory, which
  // is the check's doing, not the reader's.
  final peak = ProcessInfo.maxRss;

  // Compare what was written with what went in.
  final databaseAt = names.indexOf('books.db');
  if (databaseAt < 0) {
    problem('no books.db');
  } else {
    final target = '${out.path}/$databaseAt';
    if (File(target).lengthSync() != databaseBytes) {
      problem('books.db has another size');
    } else if (_crcOfFile(target) != databaseCrc) {
      problem('books.db has another content');
    }
  }
  var compared = 0;
  for (var i = 0; i < coverCount; i += 97) {
    final at = names.indexOf(_coverName(i));
    if (at < 0) {
      problem('no ${_coverName(i)}');
      continue;
    }
    final written = File('${out.path}/$at').readAsBytesSync();
    final expected = _picture(i, coverBytes);
    var same = written.length == expected.length;
    for (var j = 0; same && j < expected.length; j++) {
      same = written[j] == expected[j];
    }
    if (!same) problem('${_coverName(i)} has another content');
    compared++;
  }

  stdout
    ..writeln(
      'Opened and checked ${names.length} entries in '
      '${openClock.elapsedMilliseconds} ms.',
    )
    ..writeln(
      'Wrote every entry to a file in ${takeClock.elapsedMilliseconds} ms.',
    )
    ..writeln(
      'Compared: every size, the database by checksum, $compared pictures '
      'byte for byte.',
    )
    ..writeln('Peak memory of the reading: ${_megabytes(peak)}.');
  if (problems > 0) {
    stderr.writeln('$problems thing(s) wrong, see above.');
    exitCode = 1;
  } else {
    stdout.writeln('Everything came out as it went in.');
  }
}

/// The second run in the second mode: reads the backup under `root` with
/// the two steps a restore's worker isolates run (BR6).
///
/// They are called directly, one after the other, in this process: what is
/// measured is the memory the steps need, and that is the same on any
/// isolate.
void _restoreSteps({
  required String root,
  required int coverCount,
  required int coverBytes,
  required int databaseBytes,
  required int databaseCrc,
}) {
  final limits = _limitsFor(coverCount, coverBytes, databaseBytes);
  final archivePath = '$root/backup.pitabak';
  final work = Directory('$root/work')..createSync();
  final covers = Directory('$root/generation/covers');
  var problems = 0;
  void problem(String what) {
    problems++;
    stderr.writeln('WRONG: $what');
  }

  // The inspection, as the Restore page asks for it when a file is picked:
  // the reader's probe counts what is unpacked for it. Of this backup that
  // must be the manifest and nothing else, however many covers there are.
  final inspected = <int>[];
  final inspectClock = Stopwatch()..start();
  final inspection = readRestoreArchive((
    archivePath: archivePath,
    limits: limits,
    workDir: null,
  ), unpackedBytesProbe: inspected.add);
  inspectClock.stop();
  if (inspection.refusal != null || inspection.trouble != null) {
    problem('the inspection stopped');
  }
  if (inspected.length != 1 || inspected.single != _manifestText.length) {
    problem('the inspection unpacked $inspected, not the manifest alone');
  }
  if (work.listSync().isNotEmpty) problem('the inspection staged a file');

  // Step 1: the first look. The manifest into memory, the database into
  // the work folder, the covers only listed.
  final readClock = Stopwatch()..start();
  final parts = readRestoreArchive((
    archivePath: archivePath,
    limits: limits,
    workDir: work.path,
  ));
  readClock.stop();
  if (parts.refusal != null || parts.trouble != null) {
    problem('the first step stopped: ${parts.refusal ?? parts.trouble}');
  }
  if (parts.coversToWrite.length != coverCount) {
    problem('${parts.coversToWrite.length} covers listed, not $coverCount');
  }
  if (parts.coversLeftOut.isNotEmpty) {
    problem('${parts.coversLeftOut.length} covers left out');
  }

  // Step 2: every listed cover straight into its own file.
  var counted = 0;
  final coversClock = Stopwatch()..start();
  final answer = buildRestoredCovers((
    archivePath: archivePath,
    limits: limits,
    coversToWrite: parts.coversToWrite,
    activeCoversDir: '$root/no_covers_here',
    builderCoversDir: covers.path,
    progressPort: null,
  ), onCoverWritten: (done, total) => counted = done);
  coversClock.stop();
  if (answer.refusal != null || answer.trouble != null) {
    problem('the covers step stopped: ${answer.refusal ?? answer.trouble}');
  }
  if (counted != coverCount) problem('$counted covers counted');
  // Taken HERE: the comparing below reads whole pictures into memory, which
  // is the check's doing, not the restore's.
  final peak = ProcessInfo.maxRss;

  // Compare what was written with what went in.
  final database = parts.booksDbPath;
  if (database == null) {
    problem('no books.db was staged');
  } else if (File(database).lengthSync() != databaseBytes) {
    problem('books.db has another size');
  } else if (_crcOfFile(database) != databaseCrc) {
    problem('books.db has another content');
  }
  final written = covers.existsSync() ? covers.listSync().length : 0;
  if (written != coverCount) problem('$written cover files, not $coverCount');
  var compared = 0;
  for (var i = 0; i < coverCount; i += 97) {
    final file = File('${covers.path}/${_coverLeaf(i)}');
    if (!file.existsSync()) {
      problem('no ${_coverLeaf(i)}');
      continue;
    }
    final content = file.readAsBytesSync();
    final expected = _picture(i, coverBytes);
    var same = content.length == expected.length;
    for (var j = 0; same && j < expected.length; j++) {
      same = content[j] == expected[j];
    }
    if (!same) problem('${_coverLeaf(i)} has another content');
    compared++;
  }

  stdout
    ..writeln(
      'Inspection: ${inspected.length} entry unpacked '
      '(${inspected.fold<int>(0, (sum, bytes) => sum + bytes)} bytes), '
      'no cover and no database, in ${inspectClock.elapsedMilliseconds} ms.',
    )
    ..writeln(
      'First step (manifest, database, list of ${parts.coversToWrite.length} '
      'covers): ${readClock.elapsedMilliseconds} ms.',
    )
    ..writeln(
      'Covers step (every cover into its own file): '
      '${coversClock.elapsedMilliseconds} ms.',
    )
    ..writeln(
      'Compared: the database by size and checksum, the number of cover '
      'files, $compared pictures byte for byte.',
    )
    ..writeln('Peak memory of the two steps: ${_megabytes(peak)}.');
  if (problems > 0) {
    stderr.writeln('$problems thing(s) wrong, see above.');
    exitCode = 1;
  } else {
    stdout.writeln('Everything came out as it went in.');
  }
}
