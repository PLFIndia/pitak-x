import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';

class _FixedSalt implements PublishCoverSaltStore {
  _FixedSalt(this._salt);
  final List<int> _salt;
  @override
  Future<List<int>> salt() async => _salt;
}

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

    test('pathFor builds covers/<hash>.jpg', () async {
      final ids = PublishCoverIds(_FixedSalt(ascii.encode('salt-1234567890')));
      final path = await ids.pathFor(7);
      expect(path, startsWith('covers/'));
      expect(path, endsWith('.jpg'));
    });

    test(
      'pathForPeriodical is stable and domain-separated from book paths',
      () async {
        final salt = ascii.encode('salt-1234567890');
        final ids = PublishCoverIds(_FixedSalt(salt));
        // Same uid ⇒ same path (external links keep working across publishes).
        expect(
          await ids.pathForPeriodical('uid-1'),
          await ids.pathForPeriodical('uid-1'),
        );
        // A periodical whose uid happens to look like a book id still gets a
        // different path — the 'periodical:' prefix separates the domains.
        expect(await ids.pathForPeriodical('42'), isNot(await ids.pathFor(42)));
        expect(
          await ids.pathForPeriodical('uid-1'),
          'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg',
        );
      },
    );
  });
}
