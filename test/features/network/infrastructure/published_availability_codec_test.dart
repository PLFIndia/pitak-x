import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/infrastructure/published_availability_codec.dart';

/// Every `availability.json` read rule (ADR 0019 Decision 4 + its S7
/// clarification, ADR 0015 amendment), one group per rule of the codec
/// header.
///
/// The reader is ALL-OR-NOTHING (beginner note): one bad entry refuses the
/// whole file, because dropping just that key would show its item as
/// Available. So almost every test below asks one question — "accepted or
/// refused?" — and every refusal must be the one shared, detail-free
/// [PublishedAvailabilityCodec.refused] failure.
///
/// Expensive boundaries (body size, key count) use injected small caps; the
/// real 1 MiB cap gets one honest test with a padded, real-sized document.
void main() {
  const codec = PublishedAvailabilityCodec();
  const keySet = '5e0c1d2b3a497f68';
  const keyA = 'aaaaaaaaaaaaaaa1';
  const keyB = 'bbbbbbbbbbbbbbb2';

  List<int> encode(Object? json) => utf8.encode(jsonEncode(json));

  List<int> fixture(String name) =>
      File('test/fixtures/published_availability/$name').readAsBytesSync();

  /// A schema-1 document. Pass [omit] to leave a field out entirely (absent
  /// is different from `null` for some rules) and [extra] to add or replace
  /// fields.
  Map<String, Object?> document({
    Object? out = const [keyA, keyB],
    Set<String> omit = const {},
    Map<String, Object?> extra = const {},
  }) {
    final map = <String, Object?>{
      'schemaVersion': 1,
      'keySet': keySet,
      'asOf': 1761984300000,
      'out': out,
      ...extra,
    };
    omit.forEach(map.remove);
    return map;
  }

  /// Decodes [bytes] and returns the accepted file (fails the test if not).
  PublishedAvailabilityFile accepted(
    List<int> bytes, {
    PublishedAvailabilityCodec withCodec = codec,
    String? reason,
  }) {
    final result = withCodec.decode(bytes);
    expect(result.isRight(), isTrue, reason: reason ?? 'expected accepted');
    return result.toNullable()!;
  }

  /// Asserts [bytes] are refused with the ONE shared failure.
  void expectRefused(
    List<int> bytes, {
    PublishedAvailabilityCodec withCodec = codec,
    String? reason,
  }) {
    final result = withCodec.decode(bytes);
    expect(result.isLeft(), isTrue, reason: reason ?? 'expected refused');
    expect(
      result.swap().toNullable(),
      same(PublishedAvailabilityCodec.refused),
      reason: reason,
    );
  }

  group('the refusal and the defaults', () {
    test('the refusal is a detail-free ValidationFailure', () {
      const refused = PublishedAvailabilityCodec.refused;
      expect(refused, isA<ValidationFailure>());
      // The screen never says WHY a hostile file was refused.
      expect(
        (refused as ValidationFailure).message,
        'Unreadable published availability.',
      );
    });

    test('the default caps are the entity constants', () {
      expect(codec.maxBodyBytes, PublishedAvailabilityFile.maxBytes);
      expect(codec.maxKeys, PublishedAvailabilityFile.maxKeys);
      expect(codec.maxJsonDepth, PublishedAvailabilityFile.maxJsonDepth);
    });

    test('a minimal valid document is accepted with every field', () {
      final file = accepted(encode(document()));
      expect(file.keySet, keySet);
      expect(file.outKeys, {keyA, keyB});
      expect(file.asOf, 1761984300000);
    });
  });

  group('rule 1: size cap, checked before decoding', () {
    test('exactly at an injected cap is accepted, one byte over refused', () {
      final bytes = encode(document());
      accepted(
        bytes,
        withCodec: PublishedAvailabilityCodec(maxBodyBytes: bytes.length),
      );
      expectRefused(
        bytes,
        withCodec: PublishedAvailabilityCodec(maxBodyBytes: bytes.length - 1),
      );
    });

    test('the cap counts BYTES, not characters', () {
      // 'ಕ' is one character but three UTF-8 bytes: a character count would
      // let a multi-byte body slip past the cap.
      final bytes = encode(document(extra: {'note': 'ಕ'}));
      final characters = utf8.decode(bytes).length;
      expect(bytes.length, characters + 2);
      expectRefused(
        bytes,
        withCodec: PublishedAvailabilityCodec(maxBodyBytes: characters),
      );
    });

    group('the real 1 MiB cap, with a padded real-sized document', () {
      /// A valid document of exactly [length] bytes: the padding sits inside
      /// an unknown field, which the reader must ignore.
      List<int> paddedTo(int length) {
        const head =
            '{"schemaVersion":1,"keySet":"$keySet","out":["$keyA"],'
            '"padding":"';
        const tail = '"}';
        final padding = 'x' * (length - head.length - tail.length);
        final bytes = utf8.encode('$head$padding$tail');
        expect(bytes.length, length, reason: 'test helper is exact');
        return bytes;
      }

      test('one byte under the cap is accepted', () {
        final file = accepted(paddedTo(PublishedAvailabilityFile.maxBytes - 1));
        expect(file.outKeys, {keyA});
      });

      test('exactly 1 MiB is accepted', () {
        final file = accepted(paddedTo(PublishedAvailabilityFile.maxBytes));
        expect(file.outKeys, {keyA});
      });

      test('1 MiB + 1 byte is refused', () {
        expectRefused(paddedTo(PublishedAvailabilityFile.maxBytes + 1));
      });
    });
  });

  group('rule 2: UTF-8, nesting depth, JSON, an object root', () {
    test('invalid UTF-8 is refused, never thrown', () {
      expectRefused(<int>[0x7B, 0xFF, 0xFE, 0x7D]);
      // Bad bytes hidden inside a string of an otherwise valid document (an
      // overlong encoding of '/'): still the whole file is refused.
      final head = utf8.encode('{"schemaVersion":1,"keySet":"$keySet","x":"');
      final tail = utf8.encode('","out":[]}');
      expect(
        codec.decode([...head, ...tail]).isRight(),
        isTrue,
        reason: 'the same document without the bad bytes is fine',
      );
      expectRefused([...head, 0xC0, 0xAF, ...tail]);
    });

    test('not JSON is refused', () {
      for (final text in ['', ' ', '{not json', '{"schemaVersion":1,', 'nul']) {
        expectRefused(utf8.encode(text), reason: 'text "$text"');
      }
    });

    test('a root that is not an object is refused', () {
      for (final root in <Object?>[
        <Object?>[],
        [document()],
        null,
        'availability',
        42,
        true,
      ]) {
        expectRefused(encode(root), reason: 'root $root');
      }
    });

    test('depth 16 is accepted, depth 17 refused', () {
      // The root object is level 1, so N nested arrays inside it are N + 1
      // levels deep.
      accepted(encode(document(extra: {'x': _nest(15)})));
      expectRefused(encode(document(extra: {'x': _nest(16)})));
    });

    test('a nested-bracket bomb is refused without a stack overflow', () {
      final bomb = utf8.encode('${'[' * 100000}${']' * 100000}');
      expectRefused(bomb);
    });

    test('an injected depth cap is exact', () {
      // A real file nests 2 deep: root object → `out` list.
      final bytes = encode(document());
      accepted(
        bytes,
        withCodec: const PublishedAvailabilityCodec(maxJsonDepth: 2),
      );
      expectRefused(
        bytes,
        withCodec: const PublishedAvailabilityCodec(maxJsonDepth: 1),
      );
    });

    test('brackets inside strings never count as nesting', () {
      // 40 brackets inside a string value: would be depth 41 if counted.
      accepted(encode(document(extra: {'x': '[' * 40})));
      accepted(encode(document(extra: {'x': '{' * 40})));
      // An escaped quote does not end the string early, so the brackets
      // after it are still inside the string.
      accepted(encode(document(extra: {'x': '"${'[' * 40}'})));
      accepted(
        encode(
          document(
            extra: {
              'x':
                  r'\"'
                  '${'[' * 40}',
            },
          ),
        ),
      );
    });
  });

  group('rule 3: schemaVersion is a whole number, exactly 1', () {
    test('1 and the JSON double 1.0 (and 1e0) are accepted', () {
      // The web viewer's JSON.parse cannot tell 1 from 1.0: both readers
      // must agree, so the native one accepts both spellings.
      for (final text in ['1', '1.0', '1e0', '1E0', '1.00']) {
        accepted(
          utf8.encode(
            '{"schemaVersion":$text,"keySet":"$keySet","out":["$keyA"]}',
          ),
          reason: 'schemaVersion $text',
        );
      }
    });

    test('missing, null, 0, negative and non-numbers are refused', () {
      expectRefused(encode(document(omit: {'schemaVersion'})));
      for (final version in <Object?>[
        null,
        0,
        -1,
        -1.0,
        '1',
        true,
        [1],
      ]) {
        expectRefused(
          encode(document(extra: {'schemaVersion': version})),
          reason: 'schemaVersion $version',
        );
      }
    });

    test('a non-whole number is refused (1.5 is not version 1)', () {
      for (final version in <Object>[1.5, 0.5, 1.0000001]) {
        expectRefused(
          encode(document(extra: {'schemaVersion': version})),
          reason: 'schemaVersion $version',
        );
      }
    });

    test('a newer schema (2, 2.0, a huge number) is refused', () {
      // A newer format may give the same fields another meaning: the viewer
      // falls back to the inline tags rather than guess.
      for (final text in ['2', '2.0', '99', '9007199254740991']) {
        expectRefused(
          utf8.encode(
            '{"schemaVersion":$text,"keySet":"$keySet","out":["$keyA"]}',
          ),
          reason: 'schemaVersion $text',
        );
      }
    });

    test('a version beyond JavaScript-exact integers is refused', () {
      for (final text in ['9007199254740992', '1e300', '1e400']) {
        expectRefused(
          utf8.encode(
            '{"schemaVersion":$text,"keySet":"$keySet","out":["$keyA"]}',
          ),
          reason: 'schemaVersion $text',
        );
      }
    });
  });

  group('rule 4: keySet is 16 lower-case hex characters', () {
    test('any 16 lower-case hex string is accepted', () {
      for (final value in ['0000000000000000', 'ffffffffffffffff', keySet]) {
        expect(
          accepted(encode(document(extra: {'keySet': value}))).keySet,
          value,
        );
      }
    });

    test('missing, malformed or wrong-typed keySet is refused', () {
      expectRefused(encode(document(omit: {'keySet'})));
      for (final value in <Object?>[
        null,
        '',
        keySet.toUpperCase(),
        '5e0c1d2b3a497F68', // one upper-case letter
        keySet.substring(1), // 15 characters
        '${keySet}0', // 17 characters
        ' $keySet', // no trimming
        '$keySet\n',
        'ge0c1d2b3a497f68', // not hex
        1234567890123456,
        <Object?>[keySet],
        <String, Object?>{'k': keySet},
      ]) {
        expectRefused(
          encode(document(extra: {'keySet': value})),
          reason: 'keySet $value',
        );
      }
    });
  });

  group('rule 5: out is a bounded list of keys', () {
    test('an empty list is a valid "nothing is out" file', () {
      final file = accepted(encode(document(out: <Object?>[])));
      expect(file.outKeys, isEmpty);
    });

    test('missing, null or non-list out is refused', () {
      expectRefused(encode(document(omit: {'out'})));
      for (final out in <Object?>[
        null,
        keyA,
        <String, Object?>{keyA: true},
        7,
        true,
      ]) {
        expectRefused(encode(document(out: out)), reason: 'out $out');
      }
    });

    test('at an injected key cap is accepted, one over refused', () {
      const twoKeys = PublishedAvailabilityCodec(maxKeys: 2);
      accepted(encode(document(out: [keyA, keyB])), withCodec: twoKeys);
      expectRefused(
        encode(document(out: [keyA, keyB, 'ccccccccccccccc3'])),
        withCodec: twoKeys,
      );
    });

    test('the key cap counts entries BEFORE duplicates merge', () {
      // Three entries, two distinct keys: still over a cap of two, so a
      // padded list cannot make the reader do unbounded work.
      expectRefused(
        encode(document(out: [keyA, keyA, keyB])),
        withCodec: const PublishedAvailabilityCodec(maxKeys: 2),
      );
    });

    test('the production key cap (100,000) is exact', () {
      // 100,000 keys do not fit in 1 MiB (each entry is 19 bytes), so the
      // body cap is raised here only to make the key cap reachable.
      const roomy = PublishedAvailabilityCodec(maxBodyBytes: 4 * 1024 * 1024);
      final keys = [
        for (var i = 0; i < PublishedAvailabilityFile.maxKeys; i++)
          i.toRadixString(16).padLeft(16, '0'),
      ];
      final file = accepted(encode(document(out: keys)), withCodec: roomy);
      expect(file.outKeys, hasLength(PublishedAvailabilityFile.maxKeys));
      expectRefused(
        encode(document(out: [...keys, 'ffffffffffffffff'])),
        withCodec: roomy,
      );
    });

    test('ONE bad entry anywhere refuses the whole file', () {
      // Never a partial set: a dropped key would show its item Available.
      final badEntries = <Object?>[
        null,
        7,
        7.0,
        true,
        <Object?>[keyA],
        <String, Object?>{'key': keyA},
        '',
        keyA.toUpperCase(),
        keyA.substring(1), // 15 characters
        '${keyA}0', // 17 characters
        ' $keyA',
        '$keyA ',
        'NOT-A-KEY',
      ];
      for (final bad in badEntries) {
        for (final out in [
          [bad, keyA, keyB], // first
          [keyA, bad, keyB], // middle
          [keyA, keyB, bad], // last
          [bad], // alone
        ]) {
          expectRefused(encode(document(out: out)), reason: 'out $out');
        }
      }
    });

    test('duplicates merge into one key', () {
      final file = accepted(encode(document(out: [keyA, keyB, keyA, keyA])));
      expect(file.outKeys, {keyA, keyB});
      expect(file.outKeys, hasLength(2));
    });

    test('the returned key set is unmodifiable', () {
      final file = accepted(encode(document()));
      expect(() => file.outKeys.add(keySet), throwsUnsupportedError);
      expect(() => file.outKeys.remove(keyA), throwsUnsupportedError);
      expect(file.outKeys.clear, throwsUnsupportedError);
    });
  });

  group('rule 6: unknown fields are ignored', () {
    test('unknown scalars, lists and objects change nothing', () {
      final file = accepted(
        encode(
          document(
            extra: {
              'comment': 'hello',
              'future': {
                'nested': [1, 2, 3],
                'out': ['NOT-A-KEY'],
              },
              'in': ['NOT-A-KEY'],
              'count': 9.5,
            },
          ),
        ),
      );
      expect(file.keySet, keySet);
      expect(file.outKeys, {keyA, keyB});
      expect(file.asOf, 1761984300000);
    });
  });

  group('rule 7: asOf never refuses the file', () {
    /// The `asOf` an otherwise valid document with the raw JSON [text] as its
    /// `asOf` decodes to (the document itself must be accepted).
    int? asOfFor(String text) => accepted(
      utf8.encode(
        '{"schemaVersion":1,"keySet":"$keySet","asOf":$text,"out":[]}',
      ),
      reason: 'asOf $text',
    ).asOf;

    test('an integer is kept exactly', () {
      expect(asOfFor('1761984300000'), 1761984300000);
      expect(asOfFor('0'), 0);
      // Implausible values are still KEPT here; the screen filters them
      // through plausibleAsOf().
      expect(asOfFor('1000'), 1000);
      expect(asOfFor('-5'), -5);
    });

    test('a whole double (exponent or .0 form) is kept as an int', () {
      // A JavaScript writer may print 1761984300000 as 1.7619843e12.
      for (final text in [
        '1.761984300e12',
        '1.7619843E12',
        '1761984300000.0',
      ]) {
        final value = asOfFor(text);
        expect(value, 1761984300000, reason: 'asOf $text');
        expect(value, isA<int>());
      }
      expect(asOfFor('-0.0'), 0);
    });

    test('a non-whole double, a string or a non-number is unknown', () {
      for (final text in [
        '1761984300000.5',
        '0.1',
        '"1761984300000"',
        '"yesterday"',
        'true',
        'null',
        '[1761984300000]',
        '{"ms":1761984300000}',
      ]) {
        expect(asOfFor(text), isNull, reason: 'asOf $text');
      }
    });

    test('missing asOf is unknown, and the file is still accepted', () {
      final file = accepted(encode(document(omit: {'asOf'})));
      expect(file.asOf, isNull);
      expect(file.outKeys, {keyA, keyB});
    });

    test('the JavaScript-exact range (±(2^53 − 1)) is the boundary', () {
      expect(asOfFor('9007199254740991'), 9007199254740991);
      expect(asOfFor('-9007199254740991'), -9007199254740991);
      for (final text in [
        '9007199254740992',
        '-9007199254740992',
        '9007199254740992.0',
        // int64 minimum: `abs()` would overflow back to itself here.
        '-9223372036854775808',
        '99999999999999999999', // beyond int64: Dart reads a double
        '1e300',
        '-1e300',
        '1e400', // Infinity
        '-1e400',
      ]) {
        expect(asOfFor(text), isNull, reason: 'asOf $text');
      }
    });
  });

  group('shared fixtures (the web viewer reads the same files)', () {
    test('valid.json: unknown field ignored, duplicate merged', () {
      final file = accepted(fixture('valid.json'));
      expect(file.keySet, keySet);
      expect(file.asOf, 1761984300000);
      // Seven entries, one duplicate: six keys, including the unmatched one.
      expect(file.outKeys, {
        'aaaaaaaaaaaaaaa1',
        'aaaaaaaaaaaaaaa6',
        'aaaaaaaaaaaaaaa7',
        'aaaaaaaaaaaaaaa8',
        'aaaaaaaaaaaaaaab',
        'ffffffffffffffff',
      });
    });

    test('empty_out.json is a valid "nothing is out" file', () {
      final file = accepted(fixture('empty_out.json'));
      expect(file.outKeys, isEmpty);
      expect(file.asOf, 1761984300000);
    });

    test('every asof_* fixture is accepted; asOf is kept or unknown', () {
      final expected = <String, int?>{
        'asof_in_future.json': 4102444800000,
        'asof_too_early.json': 1000,
        'asof_not_a_number.json': null,
        'asof_missing.json': null,
      };
      for (final MapEntry(key: name, value: asOf) in expected.entries) {
        final file = accepted(fixture(name), reason: name);
        expect(file.asOf, asOf, reason: name);
        expect(file.outKeys, hasLength(6), reason: name);
      }
    });

    test('other_key_set.json is ACCEPTED: binding is checked by the merge', () {
      final file = accepted(fixture('other_key_set.json'));
      expect(file.keySet, '0000000000000000');
      expect(file.outKeys, hasLength(6));
    });

    test('every broken fixture is refused as a whole', () {
      for (final name in [
        'missing_key_set.json',
        'malformed_key_set.json',
        'newer_schema.json',
        'bad_key.json',
        'out_not_a_list.json',
        'out_has_number.json',
        'no_schema_version.json',
        'not_json.json',
        'root_is_list.json',
      ]) {
        expectRefused(fixture(name), reason: name);
      }
    });

    test('a books.json is never mistaken for an availability file', () {
      for (final name in [
        'catalogue.json',
        'catalogue_no_key_set.json',
        'catalogue_bad_key_set.json',
      ]) {
        expectRefused(fixture(name), reason: name);
      }
    });
  });

  group('toString', () {
    test('names the count only, never a key, the keySet or asOf', () {
      final file = accepted(fixture('valid.json'));
      final text = file.toString();
      expect(text, 'PublishedAvailabilityFile(6 out)');
      expect(text, isNot(contains(keySet)));
      expect(text, isNot(contains('aaaaaaaaaaaaaaa1')));
      expect(text, isNot(contains('1761984300000')));
    });
  });
}

/// A real nested value [depth] arrays deep (a JSON-encoded string of brackets
/// would be ignored by the string-aware scan — that is the point of it).
Object? _nest(int depth) => depth == 0 ? 1 : <Object?>[_nest(depth - 1)];
