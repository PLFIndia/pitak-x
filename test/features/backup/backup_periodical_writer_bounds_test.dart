import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

/// Direct writer proof for the periodicals.json byte bound. The companion
/// item_kinds bounds already live in backup_archive_writer_test.dart.
void main() {
  late Directory tmp;
  late BackupArchiveWriter writer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('periodical_writer_bounds');
    writer = BackupArchiveWriter(
      vaultStore: VaultStore(baseDir: '${tmp.path}/novault'),
      coversDir: '${tmp.path}/covers',
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('an oversized periodicals entry is refused before file work', () async {
    // Fat UIDs make 600 rows cross the reader's 4 MiB cap without a slow,
    // memory-heavy million-row fixture. This is the same direct-writer shape
    // as the existing item_kinds byte-overflow regression.
    final periodicals = [
      for (var i = 0; i < 600; i++)
        Periodical(title: 'Series $i', periodicalUid: 'p$i${'x' * 7500}'),
    ];

    final result = await writer.build(
      books: const [],
      wishlist: const [],
      periodicals: periodicals,
      workDir: '${tmp.path}/work_big_periodicals',
      exportedAt: 1,
      identityJson: null,
      networkJson: null,
    );

    final failure = result.getLeft().toNullable();
    expect(failure, isA<BackupTooLargeFailure>());
    expect((failure! as BackupTooLargeFailure).detail, 'periodicalsTooLarge');
    expect(result.toNullable(), isNull);
    expect(Directory('${tmp.path}/work_big_periodicals').existsSync(), isFalse);
  });
}
