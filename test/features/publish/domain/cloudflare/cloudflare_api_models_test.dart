import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// SPECIFICATION of the Cloudflare API domain models (plan E.1/G/R18/R19).
void main() {
  const jwt = 'header.payload.signature';

  group('token and account results', () {
    test('only the exact active status is active', () {
      const active = CloudflareTokenVerification(
        status: 'active',
        expiresOn: null,
      );
      const expired = CloudflareTokenVerification(
        status: 'expired',
        expiresOn: null,
      );

      expect(active.isActive, isTrue);
      expect(expired.isActive, isFalse);
    });

    test('verification retains the optional expiry', () {
      final expiry = DateTime.utc(2027, 1, 2);
      final result = CloudflareTokenVerification(
        status: 'active',
        expiresOn: expiry,
      );

      expect(result.expiresOn, same(expiry));
    });

    test('account listing defensively copies its account list', () {
      final account = CloudflareAccount(
        id: CloudflareAccountId.tryParse('0123456789abcdef0123456789abcdef')!,
        name: 'Library account',
      );
      final source = <CloudflareAccount>[account];
      final listing = CloudflareAccountListing(
        accounts: source,
        truncated: true,
      );
      source.clear();

      expect(listing.accounts, [account]);
      expect(listing.accounts.single.name, 'Library account');
      expect(listing.truncated, isTrue);
      expect(() => listing.accounts.add(account), throwsUnsupportedError);
    });

    test('subdomain check keeps the candidate and availability', () {
      final candidate = CloudflareSubdomain.tryParse('Library')!;
      final result = CloudflareSubdomainCheckResult(
        candidate: candidate,
        availability: CloudflareSubdomainAvailability.unknown,
      );

      expect(result.candidate, same(candidate));
      expect(result.availability, CloudflareSubdomainAvailability.unknown);
    });

    test('worker route keeps both independent booleans', () {
      const route = CloudflareWorkerRoute(
        enabled: true,
        previewsEnabled: false,
      );

      expect(route.enabled, isTrue);
      expect(route.previewsEnabled, isFalse);
    });
  });

  group('asset inputs', () {
    test('manifest entry keeps a SitePath, hash and raw size', () {
      final path = SitePath.tryParse('books.json')!;
      final entry = CloudflareAssetManifestEntry(
        path: path,
        hash: 'a' * 32,
        size: 123,
      );

      expect(entry.path, same(path));
      expect(entry.hash, 'a' * 32);
      expect(entry.size, 123);
    });

    test('bucket asset reopens validated raw bytes', () async {
      const bytes = <int>[0, 1, 255];
      final asset = CloudflareBucketAsset(
        hash: '0123456789abcdef0123456789abcdef',
        type: CloudflareContentType.jpeg,
        size: bytes.length,
        openBytes: () => Stream.value(bytes),
      );

      expect(asset.type.header, 'image/jpeg');
      expect(await asset.openValidated().toList(), [bytes]);
      expect(await asset.openValidated().toList(), [bytes]);
    });

    test(
      'bucket source rejects oversized chunks and wrong total sizes',
      () async {
        CloudflareBucketAsset source(int size, List<int> bytes) =>
            CloudflareBucketAsset(
              hash: 'a' * 32,
              type: CloudflareContentType.json,
              size: size,
              openBytes: () => Stream.value(bytes),
            );
        final invalid = [
          source(CloudflareLimits.maxArtifactChunkBytes + 1, [
            ...List<int>.filled(CloudflareLimits.maxArtifactChunkBytes + 1, 0),
          ]),
          source(2, [1, 2, 3]),
          source(3, [1, 2]),
          source(1, [256]),
        ];
        for (final asset in invalid) {
          await expectLater(
            asset.openValidated().toList(),
            throwsA(isA<CloudflareByteSourceException>()),
          );
        }
      },
    );

    test('bucket source errors are redacted and fixed', () async {
      const rawError = 'private file path and platform details';
      final asset = CloudflareBucketAsset(
        hash: 'a' * 32,
        type: CloudflareContentType.json,
        size: 1,
        openBytes: () => Stream.error(Exception(rawError)),
      );
      await expectLater(
        asset.openValidated().toList(),
        throwsA(
          isA<CloudflareByteSourceException>().having(
            (error) => error.toString(),
            'redacted',
            isNot(contains(rawError)),
          ),
        ),
      );
    });
  });

  group('CloudflareCompletionToken', () {
    test('accepts visible ASCII and exposes it only through use', () {
      final token = CloudflareCompletionToken.tryParse(jwt)!;

      expect(token.use((value) => value), jwt);
      expect(token.toString(), 'CloudflareCompletionToken(***)');
      expect(token.toString(), isNot(contains(jwt)));
    });

    test('accepts the exact 16 KiB boundary and refuses one more', () {
      expect(
        CloudflareCompletionToken.tryParse(
          'a' * CloudflareCompletionToken.maxLength,
        ),
        isNotNull,
      );
      expect(
        CloudflareCompletionToken.tryParse(
          'a' * (CloudflareCompletionToken.maxLength + 1),
        ),
        isNull,
      );
    });

    for (final hostile in <String?>[
      null,
      '',
      ' ',
      ' token',
      'token ',
      'token\n',
      'token\t',
      'to ken',
      'tökén',
      'token\u0000',
    ]) {
      test('refuses invalid JWT shape "$hostile"', () {
        expect(CloudflareCompletionToken.tryParse(hostile), isNull);
      });
    }
  });

  group('CloudflareUploadSession', () {
    test('copies buckets and redacts the upload JWT', () {
      final first = <String>['a' * 32];
      final source = <List<String>>[
        first,
        ['b' * 32],
      ];
      final session = CloudflareUploadSession.tryCreate(
        uploadJwt: jwt,
        buckets: source,
      )!;
      first[0] = 'c' * 32;
      source.clear();

      expect(session.useUploadJwt((value) => value), jwt);
      expect(session.buckets, [
        ['a' * 32],
        ['b' * 32],
      ]);
      expect(session.toString(), 'CloudflareUploadSession(***)');
      expect(session.toString(), isNot(contains(jwt)));
      expect(() => session.buckets.add(const []), throwsUnsupportedError);
      expect(() => session.buckets[0].add('d' * 32), throwsUnsupportedError);
    });

    test('empty buckets make the session JWT the completion token', () {
      final session = CloudflareUploadSession.tryCreate(
        uploadJwt: jwt,
        buckets: const [],
      )!;

      final completion = session.completionTokenWhenDeduplicated;
      expect(completion, isNotNull);
      expect(completion!.use((value) => value), jwt);
    });

    test('only an empty outer bucket list is fully deduplicated', () {
      final requested = CloudflareUploadSession.tryCreate(
        uploadJwt: jwt,
        buckets: [
          ['a' * 32],
        ],
      )!;

      expect(requested.completionTokenWhenDeduplicated, isNull);
      expect(
        CloudflareUploadSession.tryCreate(uploadJwt: jwt, buckets: const [[]]),
        isNull,
        reason: 'an empty inner bucket is a malformed server response',
      );
    });

    test('session rejects the same invalid JWT shapes', () {
      for (final invalid in <String?>[null, '', 'bad jwt', 'é', 'a\nb']) {
        expect(
          CloudflareUploadSession.tryCreate(
            uploadJwt: invalid,
            buckets: const [],
          ),
          isNull,
        );
      }
    });

    for (final invalidHash in <String>[
      '',
      'a' * 31,
      'a' * 33,
      'A' * 32,
      'g' * 32,
    ]) {
      test('rejects malformed requested hash "$invalidHash"', () {
        expect(
          CloudflareUploadSession.tryCreate(
            uploadJwt: jwt,
            buckets: [
              [invalidHash],
            ],
          ),
          isNull,
        );
      });
    }

    test('rejects duplicate hashes within and across buckets', () {
      final hash = 'a' * 32;
      for (final buckets in <List<List<String>>>[
        [
          [hash, hash],
        ],
        [
          [hash],
          [hash],
        ],
      ]) {
        expect(
          CloudflareUploadSession.tryCreate(uploadJwt: jwt, buckets: buckets),
          isNull,
        );
      }
    });

    test('accepts 20000 unique hashes and refuses 20001', () {
      final atLimit = <String>[
        for (var i = 0; i < CloudflareLimits.maxFilesPerVersion; i++) _hash(i),
      ];
      expect(
        CloudflareUploadSession.tryCreate(uploadJwt: jwt, buckets: [atLimit]),
        isNotNull,
      );

      final overLimit = <String>[...atLimit, _hash(atLimit.length)];
      expect(
        CloudflareUploadSession.tryCreate(uploadJwt: jwt, buckets: [overLimit]),
        isNull,
      );
    });
  });

  group('deployment protocol values', () {
    test('live config is the exact R26 shape', () {
      expect(CloudflareDeploymentKind.live.htmlHandling, 'auto-trailing-slash');
      expect(CloudflareDeploymentKind.live.notFoundHandling, 'none');
      expect(
        CloudflareDeploymentKind.live.headers,
        '/*\n'
        '  Cache-Control: no-cache\n'
        '  Access-Control-Allow-Origin: *\n',
      );
    });

    test('retired config is the exact R27 shape', () {
      expect(
        CloudflareDeploymentKind.retired.htmlHandling,
        'auto-trailing-slash',
      );
      expect(CloudflareDeploymentKind.retired.notFoundHandling, '404-page');
      expect(
        CloudflareDeploymentKind.retired.headers,
        '/*\n'
        '  Cache-Control: no-cache\n'
        "  Content-Security-Policy: default-src 'none'; "
        "style-src 'unsafe-inline'; base-uri 'none'; "
        "form-action 'none'; frame-ancestors 'none'\n"
        '  X-Content-Type-Options: nosniff\n'
        '  Referrer-Policy: no-referrer\n',
      );
    });

    test(
      'recovery callback returns an explicit remote-state decision',
      () async {
        Future<CloudflareDeployRecovery> recovery() async =>
            CloudflareDeployRecovery.alreadyDeployed;

        expect(await recovery(), CloudflareDeployRecovery.alreadyDeployed);
        expect(CloudflareDeployRecovery.values, [
          CloudflareDeployRecovery.retry,
          CloudflareDeployRecovery.alreadyDeployed,
          CloudflareDeployRecovery.abort,
        ]);
      },
    );
  });

  group('CloudflareApiException', () {
    test('retains only safe typed diagnostics and copies error codes', () {
      final codes = <int>[10007, 10032];
      final error = CloudflareApiException(
        CloudflareApiExceptionKind.malformedResponse,
        statusCode: 400,
        errorCodes: codes,
        uncertain: true,
      );
      codes.clear();

      expect(error.kind, CloudflareApiExceptionKind.malformedResponse);
      expect(error.statusCode, 400);
      expect(error.errorCodes, [10007, 10032]);
      expect(error.uncertain, isTrue);
      expect(error.message, 'Cloudflare returned an unreadable response.');
      expect(() => error.errorCodes.add(1), throwsUnsupportedError);
    });

    test('toString is fixed and cannot contain secret or response text', () {
      const secret = 'secret-token-or-response-text';
      final error = CloudflareApiException(CloudflareApiExceptionKind.network);

      expect(error.toString(), 'CloudflareApiException(${error.message})');
      expect(error.toString(), isNot(contains(secret)));
    });
  });
}

String _hash(int value) => value.toRadixString(16).padLeft(32, '0');
