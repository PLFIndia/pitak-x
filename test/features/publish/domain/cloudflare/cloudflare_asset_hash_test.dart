import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// SPECIFICATION of the Cloudflare asset hash (Cloudflare plan B.7, J.1).
///
/// The formula is pinned by fixed vectors, including the two cases that are
/// easy to get wrong: an EMPTY file (base64 is the empty string, so the hash is
/// the digest of the extension alone) and an extension whose CASE differs
/// (`html` and `HTML` must not collide).
///
/// The expected values were computed independently:
/// `hex(sha256(base64(bytes) + extension))[0..32]`.
void main() {
  group('fixed vectors', () {
    test('an empty file hashes the extension alone', () {
      expect(
        CloudflareAssetHash.of(const [], 'json'),
        '02bd175f329720378ce83dd56a1b6b1f',
      );
    });

    test('"hello" as html', () {
      expect(
        CloudflareAssetHash.of(utf8.encode('hello'), 'html'),
        '5deeda9d2277e0ed541bfc03adafb3cf',
      );
    });

    test('extension case is preserved, so HTML is a different hash', () {
      expect(
        CloudflareAssetHash.of(utf8.encode('hello'), 'HTML'),
        'b25269efb2880048d109254e4078690a',
      );
      expect(
        CloudflareAssetHash.of(utf8.encode('hello'), 'HTML'),
        isNot(CloudflareAssetHash.of(utf8.encode('hello'), 'html')),
      );
    });

    test('binary bytes are base64-encoded before hashing', () {
      expect(
        CloudflareAssetHash.of(const [0, 1, 2, 255], 'jpg'),
        'ea5d106a73084f9d717f0e41b71f7dec',
      );
    });

    test('a JSON body', () {
      expect(
        CloudflareAssetHash.of(utf8.encode('{"a":1}'), 'json'),
        '76d814c74b9a04f2d6e0c6e9fa12957a',
      );
    });
  });

  group('shape', () {
    test('is exactly 32 lower-case hex characters', () {
      final hash = CloudflareAssetHash.of(utf8.encode('x'), 'json');

      expect(hash.length, CloudflareAssetHash.hexLength);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hash), isTrue);
    });

    test('the scheme name is stored with every manifest', () {
      expect(CloudflareAssetHash.scheme, 'sha256-b64-ext-32');
    });
  });

  group('forPath refuses a type Pitak does not publish', () {
    test('accepts the three published types', () {
      expect(
        CloudflareAssetHash.forPath(
          utf8.encode('x'),
          SitePath.tryParse('books.json')!,
        ),
        isNotNull,
      );
      expect(
        CloudflareAssetHash.forPath(
          utf8.encode('x'),
          SitePath.tryParse('index.html')!,
        ),
        isNotNull,
      );
      expect(
        CloudflareAssetHash.forPath(
          utf8.encode('x'),
          SitePath.tryParse('covers/a.jpg')!,
        ),
        isNotNull,
      );
    });

    test('refuses an unknown or upper-case extension', () {
      for (final path in <String>['a.png', 'a.JPG', 'README', 'a.']) {
        expect(
          CloudflareAssetHash.forPath(
            utf8.encode('x'),
            SitePath.tryParse(path)!,
          ),
          isNull,
          reason: path,
        );
      }
    });
  });
}
