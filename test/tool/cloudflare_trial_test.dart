import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';

import '../../tool/cloudflare_trial/trial_assets.dart';
import '../../tool/cloudflare_trial/trial_cleanup.dart';
import '../../tool/cloudflare_trial/trial_http.dart';
import '../../tool/cloudflare_trial/trial_multipart.dart';
import '../../tool/cloudflare_trial/trial_public.dart';
import '../../tool/cloudflare_trial/trial_report.dart';
import '../../tool/cloudflare_trial/trial_versions.dart';

/// SPECIFICATION of the trial tool's pure parts (Cloudflare plan Part L).
///
/// The tool itself needs a disposable account, but its bodies and asset sets
/// are pure — and a mistake there would waste a real trial run, so they are
/// pinned here. Nothing in this file touches the network.
void main() {
  group('the small asset set', () {
    test('has five paths and four unique hashes', () {
      final assets = TrialAssets.small();

      expect(assets, hasLength(5));
      expect({for (final asset in assets) asset.hash}, hasLength(4));
    });

    test('the duplicate path is byte-identical to its original', () {
      final assets = TrialAssets.small();
      final original = assets.firstWhere(
        (asset) => asset.path == 'covers/sample.jpg',
      );
      final copy = assets.firstWhere(
        (asset) => asset.path == 'covers/sample-copy.jpg',
      );

      expect(copy.hash, original.hash);
    });

    test('every manifest key has exactly one leading slash', () {
      for (final asset in TrialAssets.small()) {
        expect(asset.manifestKey, startsWith('/'));
        expect(asset.manifestKey, isNot(startsWith('//')));
        expect(asset.manifestKey.substring(1), asset.path);
      }
    });

    test('the second set drops events.json and keeps the rest', () {
      final paths = TrialAssets.withoutEvents().map((a) => a.path).toList();

      expect(paths, isNot(contains('events.json')));
      expect(paths, contains('books.json'));
      expect(paths, contains('covers/sample.jpg'));
    });

    test('the third set changes only books.json', () {
      final before = {
        for (final asset in TrialAssets.withoutEvents()) asset.path: asset.hash,
      };
      final after = {
        for (final asset in TrialAssets.withChangedBooks())
          asset.path: asset.hash,
      };

      expect(after.keys, before.keys);
      expect(after['books.json'], isNot(before['books.json']));
      expect(after['index.html'], before['index.html']);
    });
  });

  group('multipart bodies', () {
    test('a bucket part is named by its hash and carries its type', () {
      final asset = TrialAssets.small().first;
      final body = utf8.decode(
        TrialMultipart.bucketBody(boundary: 'B', assets: [asset]),
      );

      expect(
        body,
        contains(
          'Content-Disposition: form-data; name="${asset.hash}"; '
          'filename="${asset.hash}"',
        ),
      );
      expect(body, contains('Content-Type: ${asset.type.header}'));
      expect(body, contains(base64.encode(asset.bytes)));
      expect(body, endsWith('--B--\r\n'));
    });

    test('the deploy body has ONE metadata part and no file part', () {
      final body = utf8.decode(
        TrialMultipart.deployBody(
          boundary: 'B',
          completionJwt: 'jwt-value',
          htmlHandling: 'auto-trailing-slash',
          notFoundHandling: 'none',
          headers: TrialMultipart.liveHeaders,
        ),
      );

      expect(body, contains('name="metadata"'));
      expect(body, isNot(contains('filename=')));
      expect(body, contains('"html_handling":"auto-trailing-slash"'));
      expect(body, contains('"not_found_handling":"none"'));
      expect(body, contains('"jwt":"jwt-value"'));
      expect(body, contains('"compatibility_date":"2026-10-26"'));
    });

    test('the live headers are the R26 pair', () {
      expect(TrialMultipart.liveHeaders, contains('Cache-Control: no-cache'));
      expect(
        TrialMultipart.liveHeaders,
        contains('Access-Control-Allow-Origin: *'),
      );
    });

    test('the retired headers carry the full CSP and hardening headers', () {
      expect(TrialMultipart.retiredHeaders, contains("default-src 'none'"));
      expect(
        TrialMultipart.retiredHeaders,
        contains('X-Content-Type-Options: nosniff'),
      );
      expect(
        TrialMultipart.retiredHeaders,
        contains('Referrer-Policy: no-referrer'),
      );
    });
  });

  group('transport failure redaction', () {
    test(
      'API TLS failures become a fixed outcome without exception text',
      () async {
        final api = TrialHttp(
          token: 'not-a-real-token',
          userAgent: 'pitak-trial-test',
          openUrl: (method, uri) async {
            expect(method, 'GET');
            expect(
              uri.toString(),
              'https://api.cloudflare.com/client/v4/user/tokens/verify',
            );
            throw const TlsException('sensitive transport detail');
          },
        );
        addTearDown(api.close);

        final response = await api.send(
          method: 'GET',
          path: '/user/tokens/verify',
        );

        expect(response.status, 0);
        expect(response.errorLabel, 'tls');
        expect(response.label, isNot(contains('sensitive transport detail')));
      },
    );

    test(
      'public TLS failures become a fixed outcome without exception text',
      () async {
        final response = await TrialPublic.get(
          Uri.parse('https://example.com/'),
          openUrl: (_) async {
            throw const TlsException('sensitive transport detail');
          },
        );

        expect(response.status, 0);
        expect(response.errorLabel, 'tls');
        expect(response.label, isNot(contains('sensitive transport detail')));
      },
    );
  });

  group('previous trial cleanup ownership', () {
    test('accepts only exact random Worker names generated by the trial', () {
      expect(
        PreviousTrialCleanup.ownsWorkerName('pitak-trial-0123abcd'),
        isTrue,
      );
      expect(
        PreviousTrialCleanup.ownsWorkerName('pitak-trial-large-0123abcd'),
        isTrue,
      );
      expect(PreviousTrialCleanup.ownsWorkerName('library'), isFalse);
      expect(PreviousTrialCleanup.ownsWorkerName('pitak-trial-prod'), isFalse);
      expect(
        PreviousTrialCleanup.ownsWorkerName('pitak-trial-0123abcd-extra'),
        isFalse,
      );
      expect(
        PreviousTrialCleanup.ownsWorkerName('pitak-trial-0123ABCD'),
        isFalse,
      );
    });
  });

  group('version diagnostics', () {
    const versionId = 'deadbeef-0000-0000-0000-000000000000';

    TrialResponse response(
      Object? result, {
      int status = 200,
      bool success = true,
    }) {
      return TrialResponse(
        status: status,
        bytes: 0,
        headers: const {},
        elapsed: Duration.zero,
        json: {'success': success, 'result': result},
      );
    }

    test('reads result.items and refuses failed or malformed envelopes', () {
      expect(
        TrialVersions.idsFrom(
          response({
            'items': [
              {'id': versionId},
            ],
          }),
        ),
        [versionId],
      );
      expect(TrialVersions.idsFrom(response(<String, Object?>{})), isEmpty);
      expect(
        TrialVersions.idsFrom(
          response([
            {'id': versionId},
          ]),
        ),
        isNull,
      );
      expect(
        TrialVersions.idsFrom(
          response({
            'items': [
              {'id': 'not-a-version-id'},
            ],
          }),
        ),
        isNull,
      );
      expect(TrialVersions.idsFrom(response({}, status: 403)), isNull);
    });

    test('Version URLs use only the first eight UUID characters', () {
      final uri = TrialVersions.previewUri(
        versionId: versionId,
        site: Uri.parse('https://worker.account.workers.dev/'),
      );

      expect(uri.toString(), 'https://deadbeef-worker.account.workers.dev/');
      expect(
        TrialVersions.previewUri(
          versionId: 'deadbeef.invalid',
          site: Uri.parse('https://worker.account.workers.dev/'),
        ),
        isNull,
      );
    });
  });

  group('trial result completeness', () {
    test('a skipped prerequisite makes the result incomplete, not a pass', () {
      final report = TrialReport()
        ..check('T1', 'first check', pass: true)
        ..skip('T3', 'prerequisite', 'not available');

      expect(report.passed, isFalse);
      expect(report.render(), contains('RESULT: INCOMPLETE (T3)'));
      expect(report.render(), isNot(contains('RESULT: PASS')));
    });

    test('informational and manual entries do not block a complete run', () {
      final report = TrialReport()
        ..check('T1', 'first check', pass: true)
        ..info('T9', 'diagnostic', 'present')
        ..manual('T14', 'decision', 'record evidence');

      expect(report.passed, isTrue);
      expect(report.render(), contains('RESULT: PASS'));
    });
  });

  group('the large synthetic set', () {
    test('generation is deterministic', () {
      expect(TrialLargeAsset.generate(7, 64), TrialLargeAsset.generate(7, 64));
      expect(
        TrialLargeAsset.generate(7, 64),
        isNot(TrialLargeAsset.generate(8, 64)),
      );
    });

    test('the recorded hash is the hash of the regenerated bytes', () {
      final assets = TrialLargeAsset.build(count: 3, size: 128);

      for (var index = 0; index < assets.length; index++) {
        expect(
          assets[index].hash,
          CloudflareAssetHash.of(TrialLargeAsset.generate(index, 128), 'bin'),
        );
        expect(assets[index].size, 128);
      }
    });
  });
}
