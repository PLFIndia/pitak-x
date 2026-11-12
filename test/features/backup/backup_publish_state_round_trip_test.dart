import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_archive_reader.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

import '../publish/support/publish_state_fixtures.dart';
import 'test_vault_gate.dart';

/// The publishing record end to end through the REAL archive writer and the
/// REAL restore reader (plan CV6, S11): what one phone writes, the next one
/// reads — with local cover sources kept exactly for the covers the archive
/// itself carries — and nothing in the archive looks like a credential.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('publish_state_rt'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'writer → reader keeps the record and the carried cover sources',
    () async {
      final covers = Directory('${tmp.path}/covers')..createSync();
      File('${covers.path}/0b1f-uuid.jpg').writeAsBytesSync([1, 2, 3]);
      final state = archivedState();
      final built =
          (await BackupArchiveWriter(
                vaultStore: VaultStore(baseDir: '${tmp.path}/novault'),
                vaultGate: TestVaultGate(),
                coversDir: covers.path,
              ).build(
                books: const [],
                wishlist: const [],
                periodicals: const [],
                workDir: '${tmp.path}/work',
                exportedAt: 1,
                identityJson: null,
                networkJson: null,
                publishStateJson: PublishStateBackupCodec.encode(state),
              ))
              .getOrElse((f) => fail('unexpected: $f'));
      // BR6: read the way a restore reads it, from the file. The worker
      // takes the manifest and the record, and lists the covers the restore
      // would write; the record keeps a local source only for those.
      final parts = readRestoreArchive((
        archivePath: built.path,
        limits: BackupLimits.current,
        workDir: null,
      ));
      expect(parts.refusal, isNull);
      expect(parts.coversToWrite, ['0b1f-uuid.jpg']);
      final manifest = parseBackupManifest(
        parts.entries,
      ).getOrElse((f) => fail('unexpected: $f'));
      expect(manifest.hasPublishState, isTrue);
      final read = readBackupExtras(
        parts.entries,
        manifest,
        carriedCoverLeaves: parts.coversToWrite.toSet(),
      ).publishState!;

      // Every entry unpacked, for the scan below (the reader a restore
      // uses never unpacks them all).
      final files = BoundedZipExtractor.extract(
        File(built.path).readAsBytesSync(),
      );

      expect(read.coverSalt, archiveSalt);
      expect(read.verifiedTarget!.isSameExactTarget(archiveGitHub), isTrue);
      expect(read.gitHubRecord.fileShas, state.gitHubRecord.fileShas);
      // The fixture's local source names `covers/0b1f-uuid.jpg`, which the
      // archive carries, so it survives next to the remote one.
      expect(
        read.gitHubRecord.coverUrlByBookId,
        state.gitHubRecord.coverUrlByBookId,
      );
      expect(read.cloudflareRecord.coverUrlByBookId, {
        '1': 'covers/0b1f-uuid.jpg',
      });

      // Nothing in the whole archive looks like a credential (D.3 scan).
      for (final entry in files.entries) {
        final text = String.fromCharCodes(entry.value).toLowerCase();
        for (final word in ['token', 'bearer', 'password', 'cfut_', 'ghp_']) {
          expect(text, isNot(contains(word)), reason: '${entry.key}: $word');
        }
      }
    },
  );
}
