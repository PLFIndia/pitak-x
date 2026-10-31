import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_multipart_request.dart';

final _bucketUrl = Uri.parse(
  'https://api.cloudflare.test/accounts/a/workers/assets/upload?base64=true',
);
final _deployUrl = Uri.parse(
  'https://api.cloudflare.test/accounts/a/workers/scripts/site',
);

CloudflareBucketAsset _asset(
  List<int> bytes,
  CloudflareContentType type, {
  String? hash,
}) => CloudflareBucketAsset(
  hash: hash ?? CloudflareAssetHash.of(bytes, type.extension),
  type: type,
  size: bytes.length,
  openBytes: () => Stream.value(bytes),
);

/// Finalizes exactly once, then replaces the random boundary so the complete
/// wire shape can be pinned without pinning package:http's random generator.
Future<String> _normalizedBody(http.MultipartRequest request) async {
  final bytes = await request.finalize().toBytes();
  final contentType = request.headers['content-type']!;
  final boundary = contentType.substring(
    contentType.indexOf('boundary=') + 'boundary='.length,
  );
  return utf8.decode(bytes).replaceAll(boundary, 'BOUNDARY');
}

Future<Map<String, dynamic>> _metadata(http.MultipartRequest request) async {
  final body = await _normalizedBody(request);
  final start = body.indexOf('\r\n\r\n') + 4;
  final end = body.indexOf('\r\n--BOUNDARY--', start);
  return jsonDecode(body.substring(start, end)) as Map<String, dynamic>;
}

void main() {
  group('cloudflareBucketMultipartRequest', () {
    test(
      'pins the exact base64 parts, names, filenames, and media types',
      () async {
        final json = _asset([97], CloudflareContentType.json);
        final html = _asset([97, 98], CloudflareContentType.html);
        final request = cloudflareBucketMultipartRequest(
          url: _bucketUrl,
          assets: [json, html],
        );

        expect(request.method, 'POST');
        expect(request.url, _bucketUrl);
        expect(request.fields, isEmpty);
        expect(request.files, hasLength(2));
        expect(
          await _normalizedBody(request),
          '--BOUNDARY\r\n'
          'content-type: application/json\r\n'
          'content-disposition: form-data; name="${json.hash}"; '
          'filename="${json.hash}"\r\n'
          '\r\n'
          'YQ==\r\n'
          '--BOUNDARY\r\n'
          'content-type: text/html; charset=utf-8\r\n'
          'content-disposition: form-data; name="${html.hash}"; '
          'filename="${html.hash}"\r\n'
          '\r\n'
          'YWI=\r\n'
          '--BOUNDARY--\r\n',
        );
      },
    );

    test('builds independent requests for separate attempts', () async {
      final asset = _asset([97], CloudflareContentType.json);
      final first = cloudflareBucketMultipartRequest(
        url: _bucketUrl,
        assets: [asset],
      );
      final second = cloudflareBucketMultipartRequest(
        url: _bucketUrl,
        assets: [asset],
      );

      expect(first, isNot(same(second)));
      expect(first.files.single, isNot(same(second.files.single)));
      expect(await _normalizedBody(first), await _normalizedBody(second));
    });

    test('does not open artifact bytes until the body is read', () async {
      var opens = 0;
      final bytes = <int>[97];
      final asset = CloudflareBucketAsset(
        hash: CloudflareAssetHash.of(bytes, 'json'),
        type: CloudflareContentType.json,
        size: bytes.length,
        openBytes: () {
          opens++;
          return Stream.value(bytes);
        },
      );
      final request = cloudflareBucketMultipartRequest(
        url: _bucketUrl,
        assets: [asset],
      );
      expect(opens, 0);
      await _normalizedBody(request);
      expect(opens, 1);
    });

    test('refuses duplicate hashes', () {
      final asset = _asset([97], CloudflareContentType.json);

      expect(
        () => cloudflareBucketMultipartRequest(
          url: _bucketUrl,
          assets: [asset, asset],
        ),
        throwsA(isA<CloudflareJsonException>()),
      );
    });

    test('refuses more than the Worker file-count limit', () {
      final asset = _asset([97], CloudflareContentType.json);

      expect(
        () => cloudflareBucketMultipartRequest(
          url: _bucketUrl,
          assets: List.filled(CloudflareLimits.maxFilesPerVersion + 1, asset),
        ),
        throwsA(isA<CloudflareJsonException>()),
      );
    });

    test('refuses an oversized raw asset before hashing or encoding it', () {
      final asset = _asset(
        List<int>.filled(CloudflareLimits.maxFileBytes + 1, 0),
        CloudflareContentType.jpeg,
        hash: '0' * CloudflareAssetHash.hexLength,
      );

      expect(
        () =>
            cloudflareBucketMultipartRequest(url: _bucketUrl, assets: [asset]),
        throwsA(isA<CloudflareJsonException>()),
      );
    });

    test('refuses a hash that does not match bytes and extension', () async {
      final asset = _asset(
        [97],
        CloudflareContentType.json,
        hash: '0' * CloudflareAssetHash.hexLength,
      );

      await expectLater(
        validateCloudflareBucketAssets([asset]),
        throwsA(isA<CloudflareJsonException>()),
      );
    });

    test('validation errors are fixed and do not expose input text', () {
      const secretShapedInput = 'not-a-real-token-or-jwt-secret';
      Object? error;
      try {
        cloudflareBucketMultipartRequest(
          url: _bucketUrl,
          assets: [
            _asset([97], CloudflareContentType.json, hash: secretShapedInput),
          ],
        );
      } on Object catch (e) {
        error = e;
      }

      expect(error, isA<CloudflareJsonException>());
      expect(error.toString(), isNot(contains(secretShapedInput)));
      expect(
        error.toString(),
        'CloudflareJsonException(malformed or unbounded response)',
      );
    });

    test(
      'non-byte integer input fails with the same fixed exception',
      () async {
        await expectLater(
          validateCloudflareBucketAssets([
            _asset(
              [256],
              CloudflareContentType.json,
              hash: '0' * CloudflareAssetHash.hexLength,
            ),
          ]),
          throwsA(isA<CloudflareJsonException>()),
        );
      },
    );
  });

  group('cloudflareDeployMultipartRequest', () {
    test('pins the exact live metadata-only request', () async {
      final completion = CloudflareCompletionToken.tryParse(
        'test-completion-token',
      )!;
      final request = cloudflareDeployMultipartRequest(
        url: _deployUrl,
        completion: completion,
        kind: CloudflareDeploymentKind.live,
      );

      final expectedMetadata = jsonEncode({
        'assets': {
          'jwt': 'test-completion-token',
          'config': {
            'html_handling': 'auto-trailing-slash',
            'not_found_handling': 'none',
            '_headers':
                '/*\n'
                '  Cache-Control: no-cache\n'
                '  Access-Control-Allow-Origin: *\n',
          },
        },
        'compatibility_date': '2026-10-26',
      });
      expect(request.method, 'PUT');
      expect(request.url, _deployUrl);
      expect(request.fields.keys, ['metadata']);
      expect(request.files, isEmpty);
      expect(
        await _normalizedBody(request),
        '--BOUNDARY\r\n'
        'content-disposition: form-data; name="metadata"\r\n'
        '\r\n'
        '$expectedMetadata\r\n'
        '--BOUNDARY--\r\n',
      );
    });

    test('pins the retired config and exact R27 headers', () async {
      final completion = CloudflareCompletionToken.tryParse(
        'test-completion-token',
      )!;
      final request = cloudflareDeployMultipartRequest(
        url: _deployUrl,
        completion: completion,
        kind: CloudflareDeploymentKind.retired,
      );

      final metadata = await _metadata(request);
      final assets = metadata['assets']! as Map<String, dynamic>;
      expect(metadata['compatibility_date'], '2026-10-26');
      expect(assets['config'], {
        'html_handling': 'auto-trailing-slash',
        'not_found_handling': '404-page',
        '_headers':
            '/*\n'
            '  Cache-Control: no-cache\n'
            "  Content-Security-Policy: default-src 'none'; "
            "style-src 'unsafe-inline'; base-uri 'none'; "
            "form-action 'none'; frame-ancestors 'none'\n"
            '  X-Content-Type-Options: nosniff\n'
            '  Referrer-Policy: no-referrer\n',
      });
    });

    test('completion token diagnostics remain redacted', () {
      const secret = 'test-completion-token-that-must-not-leak';
      final completion = CloudflareCompletionToken.tryParse(secret)!;

      expect(completion.toString(), 'CloudflareCompletionToken(***)');
      expect(completion.toString(), isNot(contains(secret)));
    });
  });
}
