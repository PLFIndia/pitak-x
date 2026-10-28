import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/http_cloudflare_deploy_api.dart';

void main() {
  final account = CloudflareAccountId.tryParse(
    '0123456789abcdef0123456789abcdef',
  )!;
  final worker = CloudflareWorkerName.tryParse('My-Library')!;
  final token = CloudflareApiToken.tryParse('cfut_${'a' * 20}')!;
  final workerPath =
      '/client/v4/accounts/${account.value}/workers/scripts/My-Library';
  final delays = <Duration>[];

  HttpCloudflareDeployApi apiFor(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    final transport = CloudflareHttpTransport(
      client: MockClient(handler),
      sleep: (delay) async => delays.add(delay),
    );
    addTearDown(transport.close);
    return HttpCloudflareDeployApi(transport);
  }

  http.Response envelope(
    Object? result, {
    int status = 200,
    bool success = true,
    List<Object?> errors = const [],
  }) => http.Response(
    jsonEncode({
      'success': success,
      'errors': errors,
      'messages': <Object?>[],
      'result': result,
    }),
    status,
    headers: {'content-type': 'application/json'},
  );

  CloudflareAssetManifestEntry manifestEntry(String hash) =>
      CloudflareAssetManifestEntry(
        path: SitePath.tryParse('books.json')!,
        hash: hash,
        size: 3,
      );

  setUp(delays.clear);

  group('Worker reads and diagnostics', () {
    test(
      'Worker existence is true only for 2xx and false only for 404',
      () async {
        final statuses = [200, 404];
        final api = apiFor((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, workerPath);
          return envelope(null, status: statuses.removeAt(0), success: false);
        });
        expect(
          await api.workerExists(
            token: token,
            accountId: account,
            workerName: worker,
          ),
          isTrue,
        );
        expect(
          await api.workerExists(
            token: token,
            accountId: account,
            workerName: worker,
          ),
          isFalse,
        );
      },
    );

    test(
      'a permission failure is not Worker absence and stays redacted',
      () async {
        const rawMessage = 'raw token and response text';
        final api = apiFor(
          (_) async => envelope(
            null,
            status: 403,
            success: false,
            errors: [
              {'code': 10000, 'message': rawMessage},
            ],
          ),
        );
        await expectLater(
          api.workerExists(
            token: token,
            accountId: account,
            workerName: worker,
          ),
          throwsA(
            isA<CloudflareApiException>()
                .having(
                  (e) => e.kind,
                  'kind',
                  CloudflareApiExceptionKind.forbidden,
                )
                .having((e) => e.errorCodes, 'codes', [10000])
                .having(
                  (e) => e.toString(),
                  'redacted',
                  isNot(contains(rawMessage)),
                ),
          ),
        );
      },
    );

    test(
      'latest deployment id is optional diagnostics, never an error collapse',
      () async {
        final responses = [
          envelope({
            'deployments': [
              {'id': 'deployment-one'},
            ],
          }),
          envelope({'deployments': <Object?>[]}),
        ];
        final api = apiFor((request) async {
          expect(request.url.path, '$workerPath/deployments');
          return responses.removeAt(0);
        });
        expect(
          await api.latestDeploymentId(
            token: token,
            accountId: account,
            workerName: worker,
          ),
          'deployment-one',
        );
        expect(
          await api.latestDeploymentId(
            token: token,
            accountId: account,
            workerName: worker,
          ),
          isNull,
        );
      },
    );

    test('a malformed deployment list is a typed failure', () async {
      final api = apiFor(
        (_) async => envelope({'deployments': <String, Object?>{}}),
      );
      await expectLater(
        api.latestDeploymentId(
          token: token,
          accountId: account,
          workerName: worker,
        ),
        throwsA(isA<CloudflareApiException>()),
      );
    });
  });

  group('asset upload sessions', () {
    test('pins the leading-slash manifest and strict buckets', () async {
      final hash = 'a' * 32;
      late Map<String, dynamic> body;
      final api = apiFor((request) async {
        expect(request.url.path, '$workerPath/assets-upload-session');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return envelope({
          'jwt': 'upload.jwt',
          'buckets': [
            [hash],
          ],
        });
      });
      final session = await api.createUploadSession(
        token: token,
        accountId: account,
        workerName: worker,
        manifest: [manifestEntry(hash)],
      );
      expect(body, {
        'manifest': {
          '/books.json': {'hash': hash, 'size': 3},
        },
      });
      expect(session.buckets, [
        [hash],
      ]);
      expect(session.toString(), isNot(contains('upload.jwt')));
    });

    test('empty buckets make the session JWT the completion token', () async {
      final api = apiFor(
        (_) async => envelope({'jwt': 'deduped.jwt', 'buckets': <Object?>[]}),
      );
      final session = await api.createUploadSession(
        token: token,
        accountId: account,
        workerName: worker,
        manifest: [manifestEntry('a' * 32)],
      );
      expect(
        session.completionTokenWhenDeduplicated?.use((value) => value),
        'deduped.jwt',
      );
    });

    test(
      'unknown, duplicate, or empty requested buckets fail closed',
      () async {
        final hash = 'a' * 32;
        final invalidBuckets = <Object?>[
          [
            ['b' * 32],
          ],
          [
            [hash, hash],
          ],
          [<Object?>[]],
        ];
        for (final buckets in invalidBuckets) {
          final api = apiFor(
            (_) async => envelope({'jwt': 'upload.jwt', 'buckets': buckets}),
          );
          await expectLater(
            api.createUploadSession(
              token: token,
              accountId: account,
              workerName: worker,
              manifest: [manifestEntry(hash)],
            ),
            throwsA(isA<CloudflareApiException>()),
            reason: 'hostile buckets: $buckets',
          );
        }
      },
    );

    test('invalid manifest input fails before any HTTP call', () async {
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        return envelope(null);
      });
      await expectLater(
        api.createUploadSession(
          token: token,
          accountId: account,
          workerName: worker,
          manifest: const [],
        ),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.invalidRequest,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('an uncertain create re-reads the Worker before retrying', () async {
      final calls = <String>[];
      final api = apiFor((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (calls.length == 1) throw http.ClientException('socket reset');
        if (request.method == 'GET') {
          return envelope(null, status: 404, success: false);
        }
        return envelope({'jwt': 'upload.jwt', 'buckets': <Object?>[]});
      });
      await api.createUploadSession(
        token: token,
        accountId: account,
        workerName: worker,
        manifest: [manifestEntry('a' * 32)],
      );
      expect(calls, [
        'POST $workerPath/assets-upload-session',
        'GET $workerPath',
        'POST $workerPath/assets-upload-session',
      ]);
      expect(delays, [const Duration(seconds: 1)]);
    });
  });

  group('bucket upload and deploy', () {
    final bytes = <int>[1, 2, 3];
    final hash = CloudflareAssetHash.of(bytes, 'json');
    final assets = [
      CloudflareBucketAsset(
        hash: hash,
        type: CloudflareContentType.json,
        size: bytes.length,
        openBytes: () => Stream.value(bytes),
      ),
    ];
    final session = CloudflareUploadSession.tryCreate(
      uploadJwt: 'upload.jwt',
      buckets: [
        [hash],
      ],
    )!;

    test(
      'uses only the upload JWT and returns a redacted completion token',
      () async {
        final api = apiFor((request) async {
          expect(
            request.url.path,
            '/client/v4/accounts/${account.value}/workers/assets/upload',
          );
          expect(request.url.query, 'base64=true');
          expect(request.headers['authorization'], 'Bearer upload.jwt');
          expect(request.body, contains('AQID'));
          expect(request.body, contains('content-type: application/json'));
          return envelope({'jwt': 'completion.jwt'});
        });
        final completion = await api.uploadBucket(
          accountId: account,
          session: session,
          assets: assets,
        );
        expect(completion.use((value) => value), 'completion.jwt');
        expect(completion.toString(), isNot(contains('completion.jwt')));
      },
    );

    test(
      'retries an idempotent bucket with a fresh multipart request',
      () async {
        var calls = 0;
        var opens = 0;
        final retryAssets = [
          CloudflareBucketAsset(
            hash: hash,
            type: CloudflareContentType.json,
            size: bytes.length,
            openBytes: () {
              opens++;
              return Stream.value(bytes);
            },
          ),
        ];
        final api = apiFor((request) async {
          calls++;
          if (calls == 1) return envelope(null, status: 500, success: false);
          return envelope({'jwt': 'completion.jwt'});
        });
        await api.uploadBucket(
          accountId: account,
          session: session,
          assets: retryAssets,
        );
        expect(calls, 2);
        expect(opens, 3, reason: 'one hash pass plus one stream per attempt');
        expect(delays, [const Duration(seconds: 1)]);
      },
    );

    test('changed bytes cannot produce a completion token', () async {
      var opens = 0;
      var handlerCalls = 0;
      final changingAsset = CloudflareBucketAsset(
        hash: hash,
        type: CloudflareContentType.json,
        size: bytes.length,
        openBytes: () {
          opens++;
          return Stream.value(opens == 1 ? bytes : const [9, 9, 9]);
        },
      );
      final api = apiFor((_) async {
        handlerCalls++;
        return envelope({'jwt': 'completion.jwt'});
      });
      await expectLater(
        api.uploadBucket(
          accountId: account,
          session: session,
          assets: [changingAsset],
        ),
        throwsA(isA<CloudflareApiException>()),
      );
      expect(handlerCalls, 0, reason: 'the mismatched body cannot complete');
      expect(opens, 4, reason: 'validation plus all three bounded attempts');
      expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('three concurrent bucket calls remain serial', () async {
      var calls = 0;
      var active = 0;
      var maxActive = 0;
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final api = apiFor((_) async {
        calls++;
        active++;
        if (active > maxActive) maxActive = active;
        if (calls == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        active--;
        return envelope({'jwt': 'completion.jwt'});
      });
      final operations = List.generate(
        3,
        (_) => api.uploadBucket(
          accountId: account,
          session: session,
          assets: assets,
        ),
      );
      await firstStarted.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1, reason: 'the other two uploads wait for the first');
      releaseFirst.complete();
      await Future.wait(operations);
      expect(maxActive, 1);
    });

    test('an oversized source chunk is refused before HTTP', () async {
      var calls = 0;
      final oversizedHash = '0' * 32;
      final oversizedSession = CloudflareUploadSession.tryCreate(
        uploadJwt: 'upload.jwt',
        buckets: [
          [oversizedHash],
        ],
      )!;
      final oversized = CloudflareBucketAsset(
        hash: oversizedHash,
        type: CloudflareContentType.json,
        size: CloudflareLimits.maxArtifactChunkBytes + 1,
        openBytes: () => Stream.value(
          List<int>.filled(CloudflareLimits.maxArtifactChunkBytes + 1, 0),
        ),
      );
      final api = apiFor((_) async {
        calls++;
        return envelope({'jwt': 'completion.jwt'});
      });
      await expectLater(
        api.uploadBucket(
          accountId: account,
          session: oversizedSession,
          assets: [oversized],
        ),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.invalidRequest,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('an unrequested or empty bucket fails before HTTP', () async {
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        return envelope({'jwt': 'completion.jwt'});
      });
      await expectLater(
        api.uploadBucket(
          accountId: account,
          session: session,
          assets: const [],
        ),
        throwsA(isA<CloudflareApiException>()),
      );
      expect(calls, 0);
    });

    test(
      'deploy is metadata-only and does not invoke recovery on success',
      () async {
        var recoveries = 0;
        late String body;
        final api = apiFor((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, workerPath);
          body = request.body;
          return envelope({'ignored': true});
        });
        await api.deploy(
          token: token,
          accountId: account,
          workerName: worker,
          completionToken: CloudflareCompletionToken.tryParse(
            'completion.jwt',
          )!,
          kind: CloudflareDeploymentKind.live,
          recovery: () async {
            recoveries++;
            return CloudflareDeployRecovery.retry;
          },
        );
        expect(body, contains('name="metadata"'));
        expect(body, isNot(contains('filename=')));
        expect(body, contains('auto-trailing-slash'));
        expect(body, contains('2026-10-26'));
        expect(recoveries, 0);
      },
    );

    test(
      'an uncertain deploy retries only after recovery permits it',
      () async {
        var calls = 0;
        var recoveries = 0;
        final api = apiFor((_) async {
          calls++;
          if (calls == 1) throw http.ClientException('connection lost');
          return envelope(null);
        });
        await api.deploy(
          token: token,
          accountId: account,
          workerName: worker,
          completionToken: CloudflareCompletionToken.tryParse(
            'completion.jwt',
          )!,
          kind: CloudflareDeploymentKind.retired,
          recovery: () async {
            recoveries++;
            return CloudflareDeployRecovery.retry;
          },
        );
        expect(calls, 2);
        expect(recoveries, 1);
      },
    );

    test('an already-deployed recovery avoids a duplicate PUT', () async {
      var calls = 0;
      final api = apiFor((_) async {
        calls++;
        throw http.ClientException('connection lost');
      });
      await api.deploy(
        token: token,
        accountId: account,
        workerName: worker,
        completionToken: CloudflareCompletionToken.tryParse('completion.jwt')!,
        kind: CloudflareDeploymentKind.live,
        recovery: () async => CloudflareDeployRecovery.alreadyDeployed,
      );
      expect(calls, 1);
    });
  });

  group('route and Version URL settings', () {
    test('reads both boolean fields without string coercion', () async {
      final api = apiFor(
        (_) async => envelope({'enabled': true, 'previews_enabled': false}),
      );
      final route = await api.readWorkerRoute(
        token: token,
        accountId: account,
        workerName: worker,
      );
      expect(route.enabled, isTrue);
      expect(route.previewsEnabled, isFalse);
    });

    test('update writes then confirms the exact requested state', () async {
      final methods = <String>[];
      final api = apiFor((request) async {
        methods.add(request.method);
        if (request.method == 'POST') {
          expect(jsonDecode(request.body), {
            'enabled': true,
            'previews_enabled': false,
          });
          return envelope(null);
        }
        return envelope({'enabled': true, 'previews_enabled': false});
      });
      final route = await api.updateWorkerRoute(
        token: token,
        accountId: account,
        workerName: worker,
        enabled: true,
        previewsEnabled: false,
      );
      expect(route.previewsEnabled, isFalse);
      expect(methods, ['POST', 'GET']);
    });

    test('a read-back mismatch fails closed', () async {
      final api = apiFor((request) async {
        if (request.method == 'POST') return envelope(null);
        return envelope({'enabled': true, 'previews_enabled': true});
      });
      await expectLater(
        api.updateWorkerRoute(
          token: token,
          accountId: account,
          workerName: worker,
          enabled: true,
          previewsEnabled: false,
        ),
        throwsA(isA<CloudflareApiException>()),
      );
    });
  });
}
