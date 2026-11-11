import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_archive_builder.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

import 'test_vault_gate.dart';

/// What one build gave: its result, every report in the order it arrived,
/// and how long the build took as timed by the test.
typedef _Run = ({
  Either<Failure, BuiltBackup> result,
  List<BackupProgress> reports,
  Duration took,
});

/// BR4 rider 3 (the backup part of review finding P4-M7): the REAL writer
/// reports how many cover pictures it has packed, from its worker isolate,
/// through a real port. What these tests hold it to:
///  - the count only rises, and ends on the number of covers in the file;
///  - the number of reports is bounded by TIME, not by the number of
///    covers (at most ten a second, plus the first and the last);
///  - nothing is reported when there is nothing to count.
///
/// The rule "which counts go out" is tested with a made-up clock in
/// `backup_progress_port_test.dart`; the counting itself in
/// `backup_zip_file_test.dart`.
void main() {
  late Directory tmp;
  late Directory coversDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('backup_writer_progress_test');
    coversDir = Directory('${tmp.path}/covers')..createSync();
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Puts [count] small cover files into the covers folder.
  void covers(int count, {int bytes = 16}) {
    for (var i = 0; i < count; i++) {
      final name = 'c${i.toString().padLeft(5, '0')}.jpg';
      File('${coversDir.path}/$name').writeAsBytesSync(Uint8List(bytes));
    }
  }

  /// One build of a library that has nothing but its cover files, with a
  /// listener.
  Future<_Run> build({BackupLimits limits = BackupLimits.current}) async {
    final reports = <BackupProgress>[];
    final writer = BackupArchiveWriter(
      vaultStore: VaultStore(baseDir: '${tmp.path}/novault'),
      vaultGate: TestVaultGate(),
      coversDir: coversDir.path,
      limits: limits,
    );
    final clock = Stopwatch()..start();
    final result = await writer.build(
      books: const [],
      wishlist: const [],
      periodicals: const [],
      workDir: '${tmp.path}/run',
      exportedAt: 1700000000000,
      identityJson: null,
      networkJson: null,
      publishStateJson: null,
      onProgress: reports.add,
    );
    return (result: result, reports: reports, took: clock.elapsed);
  }

  int coversInArchive(BuiltBackup built) => BoundedZipExtractor.extract(
    File(built.path).readAsBytesSync(),
  ).keys.where((name) => name.startsWith('cover_')).length;

  void expectRising(List<BackupProgress> reports, {required int total}) {
    for (var i = 0; i < reports.length; i++) {
      expect(reports[i].coversTotal, total, reason: 'report $i');
      if (i == 0) continue;
      expect(
        reports[i].coversDone,
        greaterThan(reports[i - 1].coversDone),
        reason: 'report $i',
      );
    }
  }

  test('the count rises, ends on the number of covers in the file, and the '
      'number of reports is bounded by time', () async {
    covers(400);

    final run = await build();
    final built = run.result.getOrElse((f) => fail('unexpected left: $f'));

    expect(coversInArchive(built), 400);
    expect('${run.reports.first}', 'BackupProgress(1 of 400)');
    expect('${run.reports.last}', 'BackupProgress(400 of 400)');
    expectRising(run.reports, total: 400);
    // At most one report per tenth of a second of packing, plus the first
    // and the last. The packing took no longer than the whole build as
    // timed here, so this holds on a slow machine too. For 400 covers it
    // means a handful of reports, not 400.
    expect(
      run.reports.length,
      lessThanOrEqualTo(run.took.inMilliseconds ~/ 100 + 2),
      reason: '${run.reports.length} reports in ${run.took}',
    );
  });

  test('three covers: the first and the last count arrive, in order', () async {
    covers(3);

    final run = await build();

    expect(run.result.isRight(), isTrue);
    expect('${run.reports.first}', 'BackupProgress(1 of 3)');
    expect('${run.reports.last}', 'BackupProgress(3 of 3)');
    expect(run.reports.length, inInclusiveRange(2, 3));
    expectRising(run.reports, total: 3);
  });

  test('one cover gives exactly one report', () async {
    covers(1);

    final run = await build();

    expect(run.result.isRight(), isTrue);
    expect([for (final r in run.reports) '$r'], ['BackupProgress(1 of 1)']);
  });

  test('a library without covers reports nothing', () async {
    final run = await build();

    expect(run.result.isRight(), isTrue);
    expect(run.reports, isEmpty);
  });

  test('a cover that is too large for a backup is not counted', () async {
    // D10: such a picture is left out of the backup. "Cover 2 of 2" must
    // then mean the two that go in, not the three in the folder.
    const limits = BackupLimits(
      maxCovers: 16,
      maxContentBytes: 64 * 1024 * 1024,
      maxCoverBytes: 100,
      maxDatabaseBytes: 16 * 1024 * 1024,
      maxTextEntryBytes: 4 * 1024 * 1024,
    );
    covers(2);
    File('${coversDir.path}/too_large.jpg').writeAsBytesSync(Uint8List(101));

    final run = await build(limits: limits);
    final built = run.result.getOrElse((f) => fail('unexpected left: $f'));

    expect(coversInArchive(built), 2);
    expect('${run.reports.last}', 'BackupProgress(2 of 2)');
    expectRising(run.reports, total: 2);
  });

  test('a build that is refused before packing reports nothing', () async {
    const limits = BackupLimits(
      maxCovers: 2,
      maxContentBytes: 64 * 1024 * 1024,
      maxCoverBytes: 4 * 1024 * 1024,
      maxDatabaseBytes: 16 * 1024 * 1024,
      maxTextEntryBytes: 4 * 1024 * 1024,
    );
    covers(3);

    final run = await build(limits: limits);

    expect(run.result.getLeft().toNullable(), isA<BackupTooLargeFailure>());
    expect(run.reports, isEmpty);
  });
}
