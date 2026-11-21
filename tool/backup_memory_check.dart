// A check done BY HAND, not by CI: how much memory does building a large
// backup need? (Backup rework BR4; review finding P3-B1; safety-check
// point SC8.)
//
// WHY THIS EXISTS (beginner note): until BR4 the whole backup was built in
// memory, so a large library needed hundreds of megabytes and could crash
// the app. BR4 writes the backup straight to a file. This script drives the
// REAL writer with a large made-up library while the Dart heap is capped. If
// the writer went back to holding the backup in memory, the run would stop
// with "Out of Memory" instead of printing its numbers.
//
// What it builds, in a temporary folder that it removes again:
//  - cover pictures of random bytes (like JPEG, they do not shrink);
//  - a large file in place of the vault database. The vault is the one
//    database the writer copies from disk as it is, so it can be made large
//    without first holding a large library in memory.
//
// How to run it (from the repository root). Compile first: under plain
// `dart run` the compiler itself needs several hundred megabytes, which
// hides what the writer needs.
//
//   dart compile exe tool/backup_memory_check.dart -o /tmp/backup_memory_check
//   DART_VM_OPTIONS=--old_gen_heap_size=64 /tmp/backup_memory_check
//
// Optional arguments, in this order: the number of covers (default 10000),
// the size of one cover in bytes (default 20000), the size of the vault
// file in MiB (default 150).
//
// It runs on a computer, not on a phone: the memory figure of a phone comes
// from the device runs of BR10.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/import_export/domain/zip_container.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/domain/vault_idle_gate.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

const int _mebibyte = 1024 * 1024;

String _megabytes(int bytes) => '${(bytes / _mebibyte).toStringAsFixed(1)} MB';

/// The writer copies the vault file only while no vault operation runs. In
/// the app the vault session decides when that is. This script has no vault
/// session and nothing else touches its made-up vault, so the copy may run
/// at once.
class _NoVaultSession implements VaultIdleGate {
  const _NoVaultSession();

  @override
  Future<T> whileVaultIdle<T>(Future<T> Function() action) => action();
}

Future<void> main(List<String> arguments) async {
  final coverCount = arguments.isNotEmpty ? int.parse(arguments[0]) : 10000;
  final coverBytes = arguments.length > 1 ? int.parse(arguments[1]) : 20000;
  final vaultMebibytes = arguments.length > 2 ? int.parse(arguments[2]) : 150;

  final root = Directory.systemTemp.createTempSync('backup_memory_check_');
  try {
    final covers = Directory('${root.path}/covers')..createSync();
    final random = Random(7);
    final picture = Uint8List(coverBytes);
    for (var i = 0; i < coverCount; i++) {
      for (var j = 0; j < picture.length; j++) {
        picture[j] = random.nextInt(256);
      }
      File(
        '${covers.path}/c${i.toString().padLeft(6, '0')}.jpg',
      ).writeAsBytesSync(picture);
    }

    // The stand-in for a large vault database: random bytes, because the
    // real one is ciphertext and does not shrink either. Written in pieces
    // so that making the test data needs little memory too.
    final vault = VaultStore(baseDir: '${root.path}/vault');
    Directory('${root.path}/vault').createSync();
    final vaultFile = File(vault.dbPath).openSync(mode: FileMode.write);
    final piece = Uint8List(_mebibyte);
    for (var i = 0; i < vaultMebibytes; i++) {
      for (var j = 0; j < piece.length; j++) {
        piece[j] = random.nextInt(256);
      }
      vaultFile.writeFromSync(piece);
    }
    vaultFile.closeSync();
    vault.writeBlob('salt.iv.ciphertext');

    // Room for the made-up library. These are NOT the app's limits; the
    // limits themselves are tested in `backup_writer_limits_test.dart`.
    final limits = BackupLimits(
      maxCovers: max(coverCount, 1),
      maxContentBytes: 4 * 1024 * _mebibyte - 1,
      maxCoverBytes: max(coverBytes, 1),
      maxDatabaseBytes: max(vaultMebibytes, 1) * _mebibyte,
      maxTextEntryBytes: 4 * _mebibyte,
    );
    final writer = BackupArchiveWriter(
      vaultStore: vault,
      vaultGate: const _NoVaultSession(),
      coversDir: covers.path,
      limits: limits,
    );

    stdout.writeln(
      'Building a backup of $coverCount covers of $coverBytes bytes and a '
      '${_megabytes(vaultMebibytes * _mebibyte)} vault file...',
    );
    // The app's page always listens for progress (BR4 rider 3), so this
    // check listens too: it then measures the path the app really takes,
    // and shows how few reports a large backup sends.
    var reports = 0;
    BackupProgress? lastReport;
    final clock = Stopwatch()..start();
    final result = await writer.build(
      books: const [CatalogueItem(id: 1, title: 'One book')],
      wishlist: const [],
      periodicals: const [],
      workDir: '${root.path}/run',
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      identityJson: null,
      networkJson: null,
      publishStateJson: null,
      onProgress: (progress) {
        reports++;
        lastReport = progress;
      },
    );
    clock.stop();

    final built = result.toNullable();
    if (built == null) {
      stderr.writeln('The build was refused: ${result.getLeft().toNullable()}');
      exitCode = 1;
      return;
    }

    // Count the entries without reading the archive into memory: the list
    // of entries ends with a small record at the very end of the file.
    final archive = File(built.path);
    final length = archive.lengthSync();
    final tailLength = min(length, 64 * 1024);
    final handle = archive.openSync()..setPositionSync(length - tailLength);
    final tail = handle.readSync(tailLength);
    handle.closeSync();
    final entries = ZipContainer.locateEndRecord(tail).entryCount;
    // manifest, books.db, wishlist.db, borrowers.db, backup_blob + covers.
    final expected = coverCount + 5;
    // The last report must be the full count (none at all without covers).
    final last = lastReport;
    final progressComplete = coverCount == 0
        ? last == null
        : last != null &&
              last.coversDone == coverCount &&
              last.coversTotal == coverCount;
    final lastText = last == null
        ? 'none'
        : '${last.coversDone} of ${last.coversTotal}';

    stdout
      ..writeln('Time:            ${clock.elapsedMilliseconds} ms')
      ..writeln('Backup file:     ${_megabytes(built.sizeBytes)}')
      ..writeln('Entries:         $entries (expected $expected)')
      ..writeln('Progress:        $reports report(s), the last: $lastText')
      ..writeln('Peak memory:     ${_megabytes(ProcessInfo.maxRss)}')
      ..writeln(
        'Left in the run: '
        '${Directory('${root.path}/run').listSync().length} file(s)',
      );
    if (entries != expected || built.sizeBytes != length || !progressComplete) {
      stderr.writeln('The backup is not what was expected.');
      exitCode = 1;
    }
  } finally {
    root.deleteSync(recursive: true);
  }
}
