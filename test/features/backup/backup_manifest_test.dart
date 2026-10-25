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

    test('hasIdentity/hasNetwork default false on older archives', () {
      // §3.4: Kotlin-era and pre-network archives lack both flags, and a
      // missing flag must read as "not there", never "corrupt".
      final m = BackupManifest.tryParse(jsonEncode({'exportedAt': 1}));
      expect(m!.hasIdentity, isFalse);
      expect(m.hasNetwork, isFalse);
    });

    test('hasItemKinds/hasPeriodicals default false on older archives', () {
      // ADR 0014 W2: a flag-less (Kotlin-era or pre-v5) archive restores
      // exactly as before — every catalogue row as a book.
      final m = BackupManifest.tryParse(jsonEncode({'exportedAt': 1}));
      expect(m!.hasItemKinds, isFalse);
      expect(m.hasPeriodicals, isFalse);
    });

    test('hasItemKinds/hasPeriodicals round-trip through toJson', () {
      final parsed = BackupManifest.tryParse(
        const BackupManifest(
          exportedAt: 1,
          hasItemKinds: true,
          hasPeriodicals: true,
        ).toJson(),
      );
      expect(parsed!.hasItemKinds, isTrue);
      expect(parsed.hasPeriodicals, isTrue);
      // Tolerant parse, same _asBool leniency as the other flags.
      final lax = BackupManifest.tryParse(
        jsonEncode({'exportedAt': 1, 'hasItemKinds': 1, 'hasPeriodicals': 0}),
      );
      expect(lax!.hasItemKinds, isTrue);
      expect(lax.hasPeriodicals, isFalse);
    });

    test('hasIdentity/hasNetwork round-trip and tolerate string tokens', () {
      final parsed = BackupManifest.tryParse(
        const BackupManifest(
          exportedAt: 1,
          hasIdentity: true,
          hasNetwork: true,
        ).toJson(),
      );
      expect(parsed!.hasIdentity, isTrue);
      expect(parsed.hasNetwork, isTrue);

      // Tolerant parse: the same _asBool leniency the other flags get.
      final lax = BackupManifest.tryParse(
        jsonEncode({'exportedAt': 1, 'hasIdentity': 'true', 'hasNetwork': 1}),
      );
      expect(lax!.hasIdentity, isTrue);
      expect(lax.hasNetwork, isTrue);
    });

    test('an out-of-range schemaVersion (1e400) does not throw', () {
      // Regression: `double.toInt()` on Infinity throws UnsupportedError; the
      // doc promises tryParse "never throws". A hostile manifest must not
      // crash the restore path before its typed checks run.
      final m = BackupManifest.tryParse(
        '{"schemaVersion": 1e400, "exportedAt": 1}',
      );
      // Unparseable version falls back to the known version (defaults).
      expect(m, isNotNull);
      expect(m!.schemaVersion, BackupManifest.knownSchemaVersion);
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
