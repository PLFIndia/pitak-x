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

    test('pathFor builds covers/<hash>.jpg', () async {
      final ids = PublishCoverIds(_FixedSalt(ascii.encode('salt-1234567890')));
      final path = await ids.pathFor(7);
      expect(path, startsWith('covers/'));
      expect(path, endsWith('.jpg'));
    });
  });
}
