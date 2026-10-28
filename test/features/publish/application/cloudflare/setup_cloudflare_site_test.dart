import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../../support/cloudflare_fakes.dart';

T _right<T>(Either<Failure, T> result) => switch (result) {
  Right(value: final value) => value,
  Left(value: final failure) => fail('Expected right, got $failure'),
};

void main() {
  group('token verification and account discovery', () {
    test(
      'user token verifies before fresh storage and account listing',
      () async {
        final h = CloudflareSetupHarness();
        final discovery = _right(await h.setup.begin(cloudflareTestToken()));

        expect(h.api.userVerifyCalls, 1);
        expect(h.api.accountVerifyCalls, 0);
        expect(h.api.listCalls, 1);
        expect(h.credentials.saves, hasLength(1));
        expect(h.credentials.record?.status.accountId, isNull);
        expect(discovery.manualRequired, isFalse);
        expect(discovery.accounts, hasLength(1));
      },
    );

    test(
      'legacy 40-character token uses the user verification route',
      () async {
        final h = CloudflareSetupHarness();
        await h.setup.begin(cloudflareLegacyTestToken());
        expect(h.api.userVerifyCalls, 1);
        expect(h.api.accountVerifyCalls, 0);
      },
    );

    test('account token remains unstored until account verification', () async {
      final h = CloudflareSetupHarness();
      final token = cloudflareTestToken(account: true);
      _right(await h.setup.begin(token));

      expect(h.api.userVerifyCalls, 0);
      expect(h.api.accountVerifyCalls, 0);
      expect(h.credentials.saves, isEmpty);

      _right(
        await h.setup.selectAccount(
          accountId: cloudflareTestAccount(),
          accountName: 'Library account',
          pendingToken: token,
        ),
      );
      expect(h.api.accountVerifyCalls, 1);
      expect(
        h.credentials.record?.status.accountId?.value,
        cloudflareTestAccountId,
      );
    });

    test('inactive and expired user tokens are never stored', () async {
      final inactive = CloudflareSetupHarness();
      inactive.api.userVerification = const CloudflareTokenVerification(
        status: 'disabled',
        expiresOn: null,
      );
      expect(
        (await inactive.setup.begin(cloudflareTestToken())).isLeft(),
        isTrue,
      );
      expect(inactive.credentials.saves, isEmpty);
      expect(inactive.api.listCalls, 0);

      final expired = CloudflareSetupHarness();
      expired.api.userVerification = CloudflareTokenVerification(
        status: 'active',
        expiresOn: DateTime.fromMillisecondsSinceEpoch(
          cloudflareTestNow - 1,
          isUtc: true,
        ),
      );
      expect(
        (await expired.setup.begin(cloudflareTestToken())).isLeft(),
        isTrue,
      );
      expect(expired.credentials.saves, isEmpty);
    });

    test(
      'inactive account token is not stored after account selection',
      () async {
        final h = CloudflareSetupHarness();
        final token = cloudflareTestToken(account: true);
        h.api.accountVerification = const CloudflareTokenVerification(
          status: 'expired',
          expiresOn: null,
        );
        await h.setup.begin(token);
        final result = await h.setup.selectAccount(
          accountId: cloudflareTestAccount(),
          accountName: null,
          pendingToken: token,
        );
        expect(result.isLeft(), isTrue);
        expect(h.credentials.saves, isEmpty);
      },
    );

    test('manual Account ID still verifies an account-owned token', () async {
      final h = CloudflareSetupHarness();
      final token = cloudflareTestToken(account: true);
      h.api.listError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
      final discovery = _right(await h.setup.begin(token));
      expect(discovery.manualRequired, isTrue);

      _right(
        await h.setup.selectAccountId(
          cloudflareTestAccountId,
          pendingToken: token,
        ),
      );
      expect(h.api.accountVerifyCalls, 1);
      expect(h.credentials.record?.status.accountId, isNotNull);
    });

    test(
      'failed reconnection preserves the previous verified connection',
      () async {
        final previous = cloudflareTestConnection(writeConfirmed: true);
        final h = CloudflareSetupHarness(connection: previous);
        h.api.userVerification = const CloudflareTokenVerification(
          status: 'inactive',
          expiresOn: null,
        );

        expect((await h.setup.begin(cloudflareTestToken())).isLeft(), isTrue);
        expect(h.credentials.record, same(previous));
        expect(h.credentials.record?.status.target, isNotNull);
      },
    );

    test(
      'truncated or refused account listing requires manual Account ID',
      () async {
        final truncated = CloudflareSetupHarness();
        truncated.api.listing = CloudflareAccountListing(
          accounts: const [],
          truncated: true,
        );
        final first = _right(
          await truncated.setup.begin(cloudflareTestToken()),
        );
        expect(first.manualRequired, isTrue);

        final refused = CloudflareSetupHarness();
        refused.api.listError = CloudflareApiException(
          CloudflareApiExceptionKind.forbidden,
        );
        final second = _right(await refused.setup.begin(cloudflareTestToken()));
        expect(second.manualRequired, isTrue);
      },
    );

    test(
      'unauthorized listing is reconnect, not a manual-ID workaround',
      () async {
        final h = CloudflareSetupHarness();
        h.api.listError = CloudflareApiException(
          CloudflareApiExceptionKind.unauthorized,
        );
        expect((await h.setup.begin(cloudflareTestToken())).isLeft(), isTrue);
      },
    );

    test(
      'invalid manual Account ID fails before verification or HTTP',
      () async {
        final h = CloudflareSetupHarness();
        final result = await h.setup.selectAccountId('not-an-account');
        expect(result.isLeft(), isTrue);
        expect(h.api.accountVerifyCalls, 0);
        expect(h.api.subdomainReadCalls, 0);
      },
    );
  });

  group('subdomain setup', () {
    test(
      'API-read subdomain is confirmed without verification deploy',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withSubdomain: false,
            withWorker: false,
          ),
        );
        final result = _right(await h.setup.readSubdomain());
        expect(result.step, CloudflareSubdomainStep.confirmed);
        expect(result.subdomain?.value, 'library');
        expect(h.credentials.record?.status.addressConfirmed, isTrue);
        expect(h.api.deployCalls, 0);
      },
    );

    test(
      'explicit absence asks for creation; forbidden read offers manual',
      () async {
        final missing = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withSubdomain: false,
            withWorker: false,
          ),
        );
        missing.api.subdomain = null;
        expect(
          _right(await missing.setup.readSubdomain()).step,
          CloudflareSubdomainStep.createRequired,
        );

        final refused = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withSubdomain: false,
            withWorker: false,
          ),
        );
        refused.api.readSubdomainError = CloudflareApiException(
          CloudflareApiExceptionKind.forbidden,
        );
        expect(
          _right(await refused.setup.readSubdomain()).step,
          CloudflareSubdomainStep.manualRequired,
        );
      },
    );

    test(
      'only explicit available evidence permits subdomain creation',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withSubdomain: false,
            withWorker: false,
          ),
        );
        final result = _right(await h.setup.createSubdomain('new-library'));
        expect(result.step, CloudflareSubdomainStep.confirmed);
        expect(h.api.subdomainCheckCalls, 1);
        expect(h.api.subdomainCreateCalls, 1);
        expect(
          h.credentials.record?.status.accountSubdomain?.value,
          'new-library',
        );
      },
    );

    test('taken and unknown availability never create a subdomain', () async {
      final taken = CloudflareSetupHarness(
        connection: cloudflareTestConnection(
          withSubdomain: false,
          withWorker: false,
        ),
      );
      taken.api.availability = CloudflareSubdomainAvailability.taken;
      expect((await taken.setup.createSubdomain('taken')).isLeft(), isTrue);
      expect(taken.api.subdomainCreateCalls, 0);

      final unknown = CloudflareSetupHarness(
        connection: cloudflareTestConnection(
          withSubdomain: false,
          withWorker: false,
        ),
      );
      unknown.api.availability = CloudflareSubdomainAvailability.unknown;
      expect((await unknown.setup.createSubdomain('unknown')).isLeft(), isTrue);
      expect(unknown.api.subdomainCreateCalls, 0);
    });

    test('forbidden creation offers the manual candidate path', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(
          withSubdomain: false,
          withWorker: false,
        ),
      );
      h.api.createSubdomainError = CloudflareApiException(
        CloudflareApiExceptionKind.forbidden,
      );
      final result = _right(await h.setup.createSubdomain('candidate'));
      expect(result.step, CloudflareSubdomainStep.manualRequired);
      expect(h.credentials.record?.status.target, isNull);
    });

    test('manual subdomain stays candidate-only and has no target', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(
          withSubdomain: false,
          withWorker: false,
        ),
      );
      final result = _right(await h.setup.useManualSubdomain('guess'));
      expect(result.step, CloudflareSubdomainStep.candidate);
      expect(h.credentials.record?.status.addressConfirmed, isFalse);
      expect(h.credentials.record?.status.target, isNull);
    });
  });

  group('Worker setup and host journal', () {
    test(
      'new Worker with API-confirmed subdomain saves target without deploy',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(withWorker: false),
        );
        final ready =
            _right(await h.setup.selectWorker('new-worker'))
                as CloudflareWorkerReady;

        expect(ready.target.siteUrl, 'https://new-worker.library.workers.dev/');
        expect(ready.workersWriteConfirmed, isFalse);
        expect(h.api.deployCalls, 0);
        expect(h.hostStore.stored?.activeHost, PublishHost.cloudflare);
        expect(h.hostStore.stored?.verifiedTarget, isNull);
      },
    );

    test('existing Worker requires consent before any write', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(withWorker: false),
      );
      h.api.workerExistsValue = true;
      final consent = _right(await h.setup.selectWorker('existing'));
      expect(consent, isA<CloudflareWorkerReplacementRequired>());
      expect(h.credentials.saves, isEmpty);
      expect(h.api.deployCalls, 0);
      expect(h.api.routeUpdates, isEmpty);

      final ready = _right(
        await h.setup.selectWorker('existing', replacementConsent: true),
      );
      expect(ready, isA<CloudflareWorkerReady>());
      expect(h.api.deployCalls, 0);
    });

    test(
      'manual candidate requests verification before a remote write',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withWorker: false,
            confirmed: false,
          ),
        );
        final result = _right(await h.setup.selectWorker('candidate'));
        expect(result, isA<CloudflareVerificationRequired>());
        expect(h.credentials.saves, isEmpty);
        expect(h.api.deployCalls, 0);
        expect(h.credentials.record?.status.target, isNull);
      },
    );

    test(
      'manual proof for Worker A requires fresh proof for Worker B',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            confirmed: false,
            writeConfirmed: true,
          ),
        );
        final required = _right(await h.setup.selectWorker('worker-b'));
        expect(required, isA<CloudflareVerificationRequired>());
        expect(h.api.deployCalls, 0);
        expect(
          h.credentials.record?.status.target?.siteUrl,
          'https://pitak-library.library.workers.dev/',
        );

        h.verifier.body = cloudflareTestMarkerBytes();
        final ready =
            _right(
                  await h.setup.selectWorker(
                    'worker-b',
                    verificationConfirmed: true,
                  ),
                )
                as CloudflareWorkerReady;
        expect(ready.target.siteUrl, 'https://worker-b.library.workers.dev/');
        expect(h.api.deployCalls, 1);
      },
    );

    test('existing GitHub active/verified journal remains untouched', () async {
      final github = GitHubPublishTarget.create('me/lib')!;
      final journal = PublishHostState.empty.afterVerifiedPublish(github);
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(withWorker: false),
        hostState: journal,
      );
      _right(await h.setup.selectWorker('new-worker'));

      expect(h.hostStore.stored?.activeHost, PublishHost.github);
      expect(h.hostStore.stored?.verifiedTarget?.targetId, github.targetId);
      expect(h.hostStore.saves, 0);
    });

    test('legacy GitHub manifest prevents an implicit host switch', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(withWorker: false),
        legacyGitHubRepo: 'me/lib',
      );
      _right(await h.setup.selectWorker('new-worker'));

      expect(h.setup.currentActiveHost(), PublishHost.github);
      expect(h.hostStore.saves, 0);
      expect(h.hostStore.stored, isNull);
    });

    test('disconnect clears only the secure record', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(),
        hostState: const PublishHostState(activeHost: PublishHost.cloudflare),
      );
      expect((await h.setup.disconnect()).isRight(), isTrue);
      expect(h.credentials.record, isNull);
      expect(h.hostStore.stored?.activeHost, PublishHost.cloudflare);
      expect(h.api.deployCalls, 0);
    });

    test(
      'a storage read failure is typed, not a not-configured result',
      () async {
        final h = CloudflareSetupHarness()..credentials.failRead = true;
        expect((await h.setup.loadStatus()).isLeft(), isTrue);
      },
    );
  });
}
