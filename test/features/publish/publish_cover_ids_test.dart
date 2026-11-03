import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

/// The pure hash helpers. The cover PATHS built from them are pinned in
/// `domain/publish_cover_names_test.dart` (plan D.5).
void main() {
  group('PublishCoverIds', () {
    test('shortHashHex is 16 hex chars and deterministic', () {
      final salt = ascii.encode('salt-1234567890');
      final a = PublishCoverIds.shortHashHex(salt, 42);
      final b = PublishCoverIds.shortHashHex(salt, 42);
      expect(a, b);
      expect(a.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(a), isTrue);
    });

    test('different ids → different paths (no id leak)', () {
      final salt = ascii.encode('salt-1234567890');
      expect(
        PublishCoverIds.shortHashHex(salt, 1),
        isNot(PublishCoverIds.shortHashHex(salt, 2)),
      );
    });

    test('ASCII hashes remain byte-identical', () {
      final salt = ascii.encode('salt-1234567890');
      expect(PublishCoverIds.shortHashHex(salt, 42), 'a2b5b2e0637ead89');
      expect(
        PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1'),
        '8a6f3469e99e562b',
      );
    });

    test('non-ASCII keys hash deterministically as UTF-8', () {
      final salt = ascii.encode('salt-1234567890');
      const key = 'periodical:పత్రిక-१';
      expect(PublishCoverIds.shortHashHexForKey(salt, key), 'd6558de0d7c76239');
      expect(
        PublishCoverIds.shortHashHexForKey(salt, key),
        PublishCoverIds.shortHashHexForKey(salt, key),
      );
    });
  });
}
