import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';

/// SPECIFICATION of the public item key (ADR 0019 Decision 3, plan AV3/C.1).
///
/// A key must be: deterministic (readers join on it across publishes), in its
/// own hash domain (never equal to a cover file name), id-hiding (salted),
/// and unique within one publish (a collision fails closed).
void main() {
  final salt = ascii.encode('salt-1234567890');

  group('keyFor', () {
    test('is SHA-256(salt ‖ "item:<id>"), first 16 hex characters', () {
      // Pinned bytes: changing the formula would silently break every live
      // site's join between books.json and availability.json.
      expect(
        PublishItemKeys.keyFor(salt: salt, itemId: 42),
        '213a75ff8a85d623',
      );
      expect(
        PublishItemKeys.keyFor(salt: salt, itemId: 42),
        PublishCoverIds.shortHashHexForKey(salt, 'item:42'),
      );
    });

    test('is deterministic and has the key shape', () {
      final a = PublishItemKeys.keyFor(salt: salt, itemId: 7);
      final b = PublishItemKeys.keyFor(salt: salt, itemId: 7);
      expect(a, b);
      expect(a.length, PublishItemKeys.keyLength);
      expect(PublishItemKeys.isValidKey(a), isTrue);
    });

    test('is domain-separated from book and periodical cover names', () {
      final key = PublishItemKeys.keyFor(salt: salt, itemId: 42);
      // Book cover name for id 42 hashes '42'.
      expect(key, isNot(PublishCoverIds.shortHashHex(salt, 42)));
      expect(PublishCoverIds.shortHashHex(salt, 42), 'a2b5b2e0637ead89');
      // A periodical whose uid looks like an id hashes 'periodical:42'.
      expect(
        key,
        isNot(PublishCoverIds.shortHashHexForKey(salt, 'periodical:42')),
      );
    });

    test('depends on the salt (keys hide the internal id)', () {
      expect(
        PublishItemKeys.keyFor(salt: salt, itemId: 1),
        isNot(PublishItemKeys.keyFor(salt: ascii.encode('other'), itemId: 1)),
      );
      expect(
        PublishItemKeys.keyFor(salt: salt, itemId: 1),
        isNot(PublishItemKeys.keyFor(salt: salt, itemId: 2)),
      );
    });
  });

  group('isValidKey', () {
    test('accepts exactly 16 lower-case hex characters', () {
      expect(PublishItemKeys.isValidKey('0123456789abcdef'), isTrue);
      for (final bad in [
        '',
        '0123456789abcde',
        '0123456789abcdef0',
        '0123456789ABCDEF',
        '0123456789abcdeg',
        ' 0123456789abcde',
        '0123456789abcdef\n',
      ]) {
        expect(PublishItemKeys.isValidKey(bad), isFalse, reason: bad);
      }
    });
  });

  group('keysFor', () {
    test('keys every id with one salt read', () async {
      final store = _CountingSalt(salt);
      final result = await PublishItemKeys(store).keysFor([1, 2, 2, 42]);

      expect(store.reads, 1);
      final keys = result.getOrElse((_) => fail('expected keys'));
      expect(keys, {
        1: 'f1256752587d05c1',
        2: '1afb3bc2efa863e0',
        42: '213a75ff8a85d623',
      });
      expect(() => keys[3] = 'x', throwsUnsupportedError);
    });

    test('an empty id list is an empty map, not a failure', () async {
      final result = await PublishItemKeys(_CountingSalt(salt)).keysFor([]);
      expect(result.getOrElse((_) => fail('expected keys')), isEmpty);
    });

    test('an unreadable salt fails closed with a fixed message', () async {
      final result = await const PublishItemKeys(_ThrowingSalt()).keysFor([1]);
      expect(result.isLeft(), isTrue);
      result.swap().map(
        (failure) => expect(
          (failure as ValidationFailure).message,
          PublishItemKeys.saltUnavailableMessage,
        ),
      );
    });

    test('an empty salt is refused (keys would reveal the ids)', () async {
      final result = await PublishItemKeys(
        _CountingSalt(const []),
      ).keysFor([1]);
      expect(_message(result.swap().toNullable()), contains('publishing key'));
    });
  });

  group('requireUnique (collision handling)', () {
    test('two ids with one key fail the whole set', () {
      final result = PublishItemKeys.requireUnique({
        1: '0123456789abcdef',
        2: '0123456789abcdef',
      });
      expect(
        _message(result.swap().toNullable()),
        PublishItemKeys.collisionMessage,
      );
    });

    test('distinct keys pass through unchanged and unmodifiable', () {
      final result = PublishItemKeys.requireUnique({
        1: '0123456789abcdef',
        2: 'fedcba9876543210',
      });
      final keys = result.getOrElse((_) => fail('expected keys'));
      expect(keys, {1: '0123456789abcdef', 2: 'fedcba9876543210'});
      expect(() => keys.remove(1), throwsUnsupportedError);
    });
  });
}

String? _message(Failure? failure) =>
    failure is ValidationFailure ? failure.message : null;

final class _CountingSalt implements PublishCoverSaltStore {
  _CountingSalt(this._salt);

  final List<int> _salt;
  int reads = 0;

  @override
  Future<List<int>> salt() async {
    reads++;
    return _salt;
  }
}

final class _ThrowingSalt implements PublishCoverSaltStore {
  const _ThrowingSalt();

  @override
  Future<List<int>> salt() async => throw Exception('keystore unavailable');
}
