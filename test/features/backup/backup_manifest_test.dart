import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';

void main() {
  group('BackupManifest.tryParse', () {
    test('parses a full manifest', () {
      final m = BackupManifest.tryParse(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 999,
          'hasBooks': true,
          'hasWishlist': false,
          'hasBorrowers': true,
          'hasBackupBlob': true,
          'hasCovers': true,
          'backupHint': 'my hint',
        }),
      );
      expect(m, isNotNull);
      expect(m!.exportedAt, 999);
      expect(m.hasWishlist, isFalse);
      expect(m.hasCovers, isTrue);
      expect(m.backupHint, 'my hint');
    });

    test('applies defaults for missing optional fields', () {
      final m = BackupManifest.tryParse(jsonEncode({'exportedAt': 1}));
      expect(m, isNotNull);
      expect(m!.schemaVersion, BackupManifest.knownSchemaVersion);
      expect(m.hasBooks, isTrue);
      expect(m.hasCovers, isFalse);
      expect(m.backupHint, isNull);
    });

    test('returns null on malformed JSON', () {
      expect(BackupManifest.tryParse('{not json'), isNull);
    });

    test('returns null on non-object JSON', () {
      expect(BackupManifest.tryParse('[]'), isNull);
    });

    test('toJson round-trips through tryParse', () {
      const original = BackupManifest(
        exportedAt: 1700000000000,
        hasBorrowers: false,
        hasBackupBlob: false,
        hasCovers: true,
        backupHint: 'my hint',
      );
      final parsed = BackupManifest.tryParse(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.exportedAt, 1700000000000);
      expect(parsed.hasBorrowers, isFalse);
      expect(parsed.hasBackupBlob, isFalse);
      expect(parsed.hasCovers, isTrue);
      expect(parsed.backupHint, 'my hint');
    });

    test('toJson omits a null backupHint', () {
      const m = BackupManifest(exportedAt: 1);
      expect(m.toJson().contains('backupHint'), isFalse);
    });
  });
}
