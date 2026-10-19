import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';

/// Tests for the `identity.json` archive entry codec (docs/ARCHITECTURE.md §5.5):
/// tolerant parse of a hostile entry — the ID is re-validated through
/// `LibraryId`, and anything unusable yields null rather than a throw.
void main() {
  const validId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('BackupIdentity', () {
    test('encode → fromJson round-trips', () {
      final encoded = BackupIdentity.encode(id: validId, name: 'My Library');
      final parsed = BackupIdentity.fromJson(encoded);
      expect(parsed, isNotNull);
      expect(parsed!.id, validId);
      expect(parsed.name, 'My Library');
    });

    test('malformed JSON → null (never throws)', () {
      expect(BackupIdentity.fromJson('{not json'), isNull);
    });

    test('non-object JSON → null', () {
      expect(BackupIdentity.fromJson('[1,2]'), isNull);
    });

    test('a non-string or invalid libraryId → null', () {
      expect(
        BackupIdentity.fromJson('{"libraryId": 42, "libraryName": "x"}'),
        isNull,
      );
      // Not 16–64 lowercase hex.
      expect(
        BackupIdentity.fromJson('{"libraryId": "NOPE", "libraryName": "x"}'),
        isNull,
      );
    });

    test('a missing or blank name is fine; whitespace is trimmed', () {
      final noName = BackupIdentity.fromJson('{"libraryId": "$validId"}');
      expect(noName, isNotNull);
      expect(noName!.name, '');

      final padded = BackupIdentity.fromJson(
        '{"libraryId": "$validId", "libraryName": "  Shelves  "}',
      );
      expect(padded!.name, 'Shelves');
    });

    test('a name with control/bidi characters degrades to blank (§6)', () {
      // Trojan-Source class: bidi overrides could visually reorder the
      // adopted library name in settings (review Lows).
      final bidi = BackupIdentity.fromJson(
        '{"libraryId": "$validId", "libraryName": "My \u202ELibrary"}',
      );
      expect(bidi, isNotNull);
      expect(bidi!.name, '');
      final control = BackupIdentity.fromJson(
        '{"libraryId": "$validId", "libraryName": "My\\tLibrary"}',
      );
      expect(control!.name, '');
    });

    test('an over-long hostile name degrades to blank, keeping the ID', () {
      final huge = 'x' * 201;
      final parsed = BackupIdentity.fromJson(
        '{"libraryId": "$validId", "libraryName": "$huge"}',
      );
      // The ID is the valuable half; a 200+ char name is dropped (§6 bound).
      expect(parsed, isNotNull);
      expect(parsed!.id, validId);
      expect(parsed.name, '');
    });
  });
}
