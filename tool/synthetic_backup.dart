// Makes a backup file of a chosen size out of made-up data, and KEEPS it.
// (Backup rework, PLAN.md "Device runs", step 3; the first item of BR10.)
//
// WHY THIS EXISTS (beginner note): the device runs have to show what the
// app does with a large backup on a real phone: 4,000 covers, 4,086 (the
// most a backup holds today), one more than that, and a file close to the
// size limit. Nobody has a real library of exactly those sizes, and a real
// library must not be used for a test anyway. So this file invents one.
//
// What makes the result trustworthy:
//  - the backup is written by the app's REAL writer (`BackupArchiveWriter`),
//    so it is the file the app itself would make;
//  - every made-up book goes through the app's own gate
//    (`CatalogueItem.validate`) and names its own cover picture;
//  - every cover is a real JPEG that shows its number, so a person can see
//    on the phone that each book got ITS picture back;
//  - before the result is handed out, the reader a restore uses is asked
//    what it thinks of the file. A file that should restore must be
//    accepted; a file that is meant to be too large must be refused.
//
// What it does NOT hold: a vault (lending records). A real vault needs the
// encrypted database of the Rust core and a passphrase. The vault's way
// through backup and restore is covered on the device by the backup the
// restored app makes itself.
//
// Only made-up data is written, only inside the folder that is given, and
// nothing is sent anywhere.
//
// This file is the work; `make_synthetic_backup.dart` next to it reads the
// command line. The split lets a test call the work with small numbers
// (`test/tool/synthetic_backup_test.dart`).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/zip_entry_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/domain/vault_idle_gate.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

/// Width of a made-up cover, in pixels: what the app stores for a
/// photographed cover (decision D2).
const int syntheticCoverWidth = 240;

/// Height of a made-up cover, in pixels (decision D2).
const int syntheticCoverHeight = 360;

/// The file name of the cover of book [number] (1, 2, 3, ...).
String syntheticCoverLeaf(int number) =>
    'synthetic-${number.toString().padLeft(6, '0')}.jpg';

/// The cover of book [number] as a plain JPEG, without padding: a coloured
/// page with the number on it. The same number always gives the same bytes.
Uint8List syntheticCoverPicture(int number) {
  final picture = img.Image(
    width: syntheticCoverWidth,
    height: syntheticCoverHeight,
  );
  // A colour that changes from book to book, never too light for the
  // white number on it.
  img.fill(
    picture,
    color: img.ColorRgb8(
      40 + (number * 37) % 150,
      40 + (number * 61) % 150,
      40 + (number * 89) % 150,
    ),
  );
  final white = img.ColorRgb8(255, 255, 255);
  img.drawString(
    picture,
    'Pitak test',
    font: img.arial24,
    x: 20,
    y: 40,
    color: white,
  );
  img.drawString(
    picture,
    '$number',
    font: img.arial48,
    x: 20,
    y: 150,
    color: white,
  );
  // Quality 70 is what the app uses for a photographed cover (D2).
  return img.encodeJpg(picture, quality: 70);
}

/// Largest payload of one JPEG comment block. A block is: two bytes that
/// say "comment", two bytes with its length (which counts itself), then
/// the payload. The length is 16 bits wide, so the payload is at most
/// 65,535 - 2 bytes.
const int _maxCommentPayload = 65533;

/// What every comment block needs besides its payload: marker and length.
const int _commentOverhead = 4;

/// The cover of book [number] as a JPEG of exactly [bytes] bytes, or null
/// when that size cannot be made.
///
/// How a small picture gets a chosen size (beginner note): a JPEG file may
/// carry comments, in blocks that every decoder skips by their stated
/// length. The picture is padded with comment blocks of random bytes until
/// the file has the size asked for. It stays a valid JPEG and shows the
/// same picture. Random bytes are used because they do not shrink when the
/// backup is packed, just as a real photograph does not.
///
/// Null when [bytes] is less than the plain picture, or one to three bytes
/// more than it: a comment block has four bytes of its own.
///
/// [random] is a seeded generator ON PURPOSE (the padding is test data, not
/// a secret): the same seed makes the same file again.
Uint8List? syntheticCoverJpeg({
  required int number,
  required int bytes,
  required Random random,
}) {
  final plain = syntheticCoverPicture(number);
  var padding = bytes - plain.length;
  if (padding == 0) return plain;
  if (padding < _commentOverhead) return null;

  final at = _afterApplicationBlocks(plain);
  final out = Uint8List(bytes)..setRange(0, at, plain);
  var offset = at;
  while (padding > 0) {
    var block = min(padding, _commentOverhead + _maxCommentPayload);
    // Never leave one to three bytes for the last block: it could not be
    // written. Four bytes less here leave five to seven for it.
    final rest = padding - block;
    if (rest > 0 && rest < _commentOverhead) block -= _commentOverhead;
    final payload = block - _commentOverhead;
    out[offset] = 0xFF;
    out[offset + 1] = 0xFE; // "comment"
    out[offset + 2] = (payload + 2) >> 8;
    out[offset + 3] = (payload + 2) & 0xFF;
    for (var i = offset + _commentOverhead; i < offset + block; i++) {
      out[i] = random.nextInt(256);
    }
    offset += block;
    padding -= block;
  }
  out.setRange(offset, bytes, plain, at);
  return out;
}

/// Where the comment blocks go: behind the two bytes that start a JPEG and
/// behind the application blocks that follow them (the first of those says
/// "this is a JFIF file", and some programs expect it to come first).
int _afterApplicationBlocks(Uint8List jpeg) {
  var offset = 2;
  while (offset + 4 <= jpeg.length &&
      jpeg[offset] == 0xFF &&
      jpeg[offset + 1] >= 0xE0 &&
      jpeg[offset + 1] <= 0xEF) {
    offset += 2 + ((jpeg[offset + 2] << 8) | jpeg[offset + 3]);
  }
  return offset;
}

/// [count] made-up books, numbered from 1. Each has passed the app's own
/// gate, has a uid of its own in the form the app mints (a version 4 UUID),
/// and names the cover [syntheticCoverLeaf] of its number.
///
/// [random] is seeded on purpose, as for the covers: the uids are test
/// data, and the same seed gives the same library again.
List<CatalogueItem> syntheticBooks({
  required int count,
  required Random random,
}) => [
  for (var number = 1; number <= count; number++)
    CatalogueItem.validate(
      CatalogueItem(
        id: number,
        itemUid: _uuid(random),
        title: 'Synthetic book ${number.toString().padLeft(6, '0')}',
        author: 'Pitak test data',
        coverUrl: '${CoverPaths.prefix}${syntheticCoverLeaf(number)}',
        // 2026-01-01, one minute apart, so that sorting by date is stable.
        addedDate: 1767225600000 + number * 60000,
      ),
    ).getOrElse(
      // Not expected: it would mean this tool builds a book the app
      // refuses. Stop loudly instead of making a backup without it.
      (errors) => throw StateError(
        'Made-up book $number did not pass validation: '
        '${errors.map((e) => e.field).join(', ')}',
      ),
    ),
];

/// A version 4 UUID in lower case, from [random].
String _uuid(Random random) {
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // the standard variant
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

/// A backup this tool made and kept.
final class SyntheticBackup {
  /// Creates the description of a finished backup file.
  const SyntheticBackup({
    required this.path,
    required this.sizeBytes,
    required this.covers,
    required this.elapsed,
  });

  /// Where the backup file lies.
  final String path;

  /// Its size in bytes.
  final int sizeBytes;

  /// How many books, and so how many covers, it holds.
  final int covers;

  /// How long making it took, the covers included.
  final Duration elapsed;
}

/// The vault gate of this tool. The app's writer copies a vault only while
/// no vault operation runs, and in the app the vault session says when
/// that is. Here there is no vault and no session, so the action runs at
/// once. (Such a gate must not exist under `lib/`:
/// `backup_vault_gate_wiring_test.dart`.)
class _NoVaultSession implements VaultIdleGate {
  const _NoVaultSession();

  @override
  Future<T> whileVaultIdle<T>(Future<T> Function() action) => action();
}

/// Limits with room for [covers] covers of [coverBytes] bytes, for a file
/// that is MEANT to be more than [limits] allow. Only what the made-up
/// library needs is widened.
BackupLimits _roomFor(int covers, int coverBytes, BackupLimits limits) =>
    BackupLimits(
      maxCovers: max(covers, limits.maxCovers),
      // The most a ZIP file of the plain kind can describe.
      maxContentBytes: 4 * 1024 * 1024 * 1024 - 1,
      maxCoverBytes: max(coverBytes, limits.maxCoverBytes),
      maxDatabaseBytes: limits.maxDatabaseBytes,
      maxTextEntryBytes: limits.maxTextEntryBytes,
    );

/// What the reader of a restore says to the backup at [path] under
/// [limits]: null when it takes the file and lists exactly [covers] cover
/// pictures to write, otherwise why not.
String? _readerObjection(String path, BackupLimits limits, int covers) {
  try {
    final zip = openBackupArchive(path, limits);
    try {
      final listed = listBackupCovers(zip);
      if (listed.toWrite.length != covers || listed.leftOut.isNotEmpty) {
        return 'the reader would write ${listed.toWrite.length} of $covers '
            'covers and leave out ${listed.leftOut.length}';
      }
      return null;
    } finally {
      zip.close();
    }
  } on BoundedExtractionException catch (e) {
    return e.message;
  }
}

/// Makes one backup of [covers] made-up books, each with a cover picture
/// of exactly [coverBytes] bytes, and puts it into [outDir] as
/// `pitak-synthetic-<covers>x<coverBytes>.pitabak`.
///
/// The backup is written by the app's own writer under [limits] (the
/// app's limits unless a test passes small ones). A library that does not
/// fit is REFUSED by that writer, exactly as in the app, and the refusal
/// is returned.
///
/// With [beyondLimits] the writer is given room instead, to make a file
/// the app must refuse to RESTORE. Its name ends in `-BEYOND-LIMITS`. A
/// file that would not be refused is not handed out under that name.
/// Mind the difference (beginner note): the writer counts COVERS, the
/// reader counts ENTRIES, which are the covers plus the other files of a
/// backup (`BackupLimits.maxEntries`). A made-up backup has three other
/// files, so the reader refuses it from `maxEntries - 2` covers on, not
/// from `maxCovers + 1`.
///
/// Either way the reader a restore uses looks at the finished file first
/// (under [limits]), and the result is returned only when the reader says
/// what the name promises.
///
/// Never overwrites: when the result is there already, nothing is made.
/// Everything else this call writes lies in a work folder inside [outDir]
/// that is removed again on every way out.
///
/// [seed] decides the padding and the uids; [madeAt] is the time written
/// into the backup (now, unless a caller wants two identical files).
Future<Either<Failure, SyntheticBackup>> makeSyntheticBackup({
  required int covers,
  required int coverBytes,
  required String outDir,
  bool beyondLimits = false,
  int seed = 7,
  BackupLimits limits = BackupLimits.current,
  DateTime? madeAt,
}) async {
  if (covers < 1) {
    return left(const ValidationFailure('Ask for at least one cover.'));
  }
  final name =
      'pitak-synthetic-${covers}x$coverBytes'
      '${beyondLimits ? '-BEYOND-LIMITS' : ''}.pitabak';
  final finalPath = p.join(outDir, name);
  if (FileSystemEntity.typeSync(finalPath) != FileSystemEntityType.notFound) {
    return left(StorageFailure('$name is there already; nothing was made'));
  }

  final clock = Stopwatch()..start();
  Directory? work;
  try {
    Directory(outDir).createSync(recursive: true);
    // Inside the output folder, so that the finished file only has to be
    // renamed, not copied.
    work = Directory(outDir).createTempSync('synthetic-work-');
    final coversDir = Directory(p.join(work.path, 'covers'))..createSync();
    final random = Random(seed);
    for (var number = 1; number <= covers; number++) {
      final cover = syntheticCoverJpeg(
        number: number,
        bytes: coverBytes,
        random: random,
      );
      if (cover == null) {
        return left(
          ValidationFailure(
            'A cover of $coverBytes bytes cannot be made: the picture of '
            'book $number alone has '
            '${syntheticCoverPicture(number).length} bytes, and padding '
            'adds at least 4.',
          ),
        );
      }
      File(
        p.join(coversDir.path, syntheticCoverLeaf(number)),
      ).writeAsBytesSync(cover);
    }

    final writer = BackupArchiveWriter(
      // A folder that is never created: "this device has no vault".
      vaultStore: VaultStore(baseDir: p.join(work.path, 'vault')),
      vaultGate: const _NoVaultSession(),
      coversDir: coversDir.path,
      limits: beyondLimits ? _roomFor(covers, coverBytes, limits) : limits,
    );
    final built = await writer.build(
      books: syntheticBooks(count: covers, random: random),
      wishlist: const [],
      periodicals: const [],
      workDir: p.join(work.path, 'run'),
      exportedAt: (madeAt ?? DateTime.now()).millisecondsSinceEpoch,
      identityJson: null,
      networkJson: null,
      publishStateJson: null,
    );
    return built.flatMap((backup) {
      final objection = _readerObjection(backup.path, limits, covers);
      if (beyondLimits && objection == null) {
        // The writer counts covers, the reader counts ENTRIES (covers
        // plus the other files of a backup). A few covers more than the
        // writer makes are therefore still read.
        return left(
          ValidationFailure(
            'The reader of a restore TAKES this backup, so the app would '
            'restore it. The reader refuses more than '
            '${limits.maxEntries} entries (covers plus the three other '
            'files of a made-up backup) or more than '
            '${limits.maxContentBytes} bytes of content. Nothing was made '
            'under a name that says otherwise.',
          ),
        );
      }
      if (!beyondLimits && objection != null) {
        return left(
          StorageFailure(
            'The reader of a restore does not take the file the writer '
            'made ($objection). Nothing was kept.',
          ),
        );
      }
      File(backup.path).renameSync(finalPath);
      return right(
        SyntheticBackup(
          path: finalPath,
          sizeBytes: backup.sizeBytes,
          covers: covers,
          elapsed: clock.elapsed,
        ),
      );
    });
  } on FileSystemException catch (e) {
    // A full disk, a folder that cannot be written. The path is left out
    // of the sentence on purpose; the caller knows which folder it gave.
    return left(
      StorageFailure('A file could not be written: ${e.osError?.message}'),
    );
  } finally {
    if (work != null && work.existsSync()) work.deleteSync(recursive: true);
  }
}
