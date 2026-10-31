import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';

void main() {
  group('decodeCloudflareEnvelope', () {
    test('accepts a bounded envelope', () {
      final envelope = decodeCloudflareEnvelope(
        utf8.encode('{"success":true,"errors":[],"result":{"id":"a"}}'),
      );
      expect(envelope['success'], isTrue);
      expect(envelope['result'], {'id': 'a'});
    });

    test('accepts depth 16 and refuses depth 17 before decoding', () {
      String body(int arrayDepth) =>
          '{"success":true,"errors":[],"result":'
          '${'[' * arrayDepth}${']' * arrayDepth}}';

      expect(decodeCloudflareEnvelope(utf8.encode(body(15))), isNotEmpty);
      expect(
        () => decodeCloudflareEnvelope(utf8.encode(body(16))),
        throwsA(isA<CloudflareJsonException>()),
      );
    });

    test('brackets inside strings do not count as depth', () {
      const body =
          r'{"success":true,"errors":[],"result":{"name":"a\"[[[[[[[[[[[[[[[[[[["}}';
      expect(decodeCloudflareEnvelope(utf8.encode(body)), isNotEmpty);
    });

    test('refuses malformed UTF-8, JSON, roots and envelopes', () {
      final invalid = <List<int>>[
        [0xff],
        utf8.encode('{'),
        utf8.encode('[]'),
        utf8.encode('{"result":{}}'),
        utf8.encode('{"success":"true"}'),
        utf8.encode('{"success":false,"errors":{}}'),
      ];
      for (final bytes in invalid) {
        expect(
          () => decodeCloudflareEnvelope(bytes),
          throwsA(isA<CloudflareJsonException>()),
          reason: 'hostile input must fail closed: $bytes',
        );
      }
    });
  });

  group('bounded field readers', () {
    test('enforce map, list and string limits', () {
      expect(
        () => cloudflareObject({'a': 1, 'b': 2}, maxEntries: 1),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(
        () => cloudflareList([1, 2], maxEntries: 1),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(
        () => cloudflareString('ab', maxLength: 1),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(
        () => cloudflareString('', maxLength: 1),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(cloudflareString('', maxLength: 1, allowEmpty: true), isEmpty);
    });

    test('do not coerce hostile booleans or numbers', () {
      expect(
        () => cloudflareBool('false'),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(cloudflareBool(false), isFalse);
      expect(
        () => cloudflareInt(1.5, min: 0, max: 2),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(
        () => cloudflareInt(3, min: 0, max: 2),
        throwsA(isA<CloudflareJsonException>()),
      );
    });

    test('reads numeric error codes without retaining raw messages', () {
      const secretText = 'raw response must never escape';
      final codes = cloudflareErrorCodes({
        'errors': [
          {'code': 10007, 'message': secretText},
        ],
      });
      expect(codes, [10007]);
      expect(codes.toString(), isNot(contains(secretText)));
      expect(
        const CloudflareJsonException().toString(),
        isNot(contains(secretText)),
      );
    });

    test('refuses excessive or malformed error collections', () {
      expect(
        () => cloudflareErrorCodes({
          'errors': List.generate(33, (_) => {'code': 1}),
        }),
        throwsA(isA<CloudflareJsonException>()),
      );
      expect(
        () => cloudflareErrorCodes({
          'errors': [
            {'code': '10007'},
          ],
        }),
        throwsA(isA<CloudflareJsonException>()),
      );
    });
  });
}
