import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/setup_cloudflare_result.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../../support/cloudflare_fakes.dart';
import '../../support/move_fakes.dart';

T _right<T>(Either<Failure, T> result) => switch (result) {
  Right(value: final value) => value,
  Left(value: final failure) => fail('Expected right, got $failure'),
};

void main() {
  group('token verification and account discovery', () {
    test(
      'user token verifies before account listing and is NOT saved yet (M3)',
      () async {
        final h = CloudflareSetupHarness();
        final discovery = _right(await h.setup.begin(cloudflareTestToken()));

        expect(h.api.userVerifyCalls, 1);
        expect(h.api.accountVerifyCalls, 0);
        expect(h.api.listCalls, 1);
        // Deferred on purpose: abandoning setup halfway must keep the old,
        // working connection (fix-plan M3).
        expect(h.credentials.saves, isEmpty);
        expect(discovery.manualRequired, isFalse);
        expect(discovery.accounts, hasLength(1));
        expect(discovery.tokenExpiresOn, isNull);
      },
    );

    test(
      'a user token is saved at account selection, with its expiry',
      () async {
        final h = CloudflareSetupHarness();
        final token = cloudflareTestToken();
        final discovery = _right(await h.setup.begin(token));

        _right(
          await h.setup.selectAccount(
            accountId: cloudflareTestAccount(),
            accountName: 'Library account',
            pendingToken: token,
            tokenExpiresOn: discovery.tokenExpiresOn,
          ),
        );

        expect(h.credentials.saves, isNotEmpty);
        expect(
          h.credentials.record?.status.accountId?.value,
          cloudflareTestAccountId,
        );
        expect(h.api.userVerifyCalls, 1, reason: 'no second verify call');
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

  group('S9 — a pending move owns the target mutation', () {
    PublishHostState pendingJournal(CloudflarePublishTarget destination) =>
        PublishHostState(
          activeHost: PublishHost.github,
          verifiedTarget: moveGitHubTarget,
        ).beginMove(
          movePending(oldTarget: moveGitHubTarget, newTarget: destination),
        )!;

    test(
      'finishSetup is allowed for the exact pending destination Worker',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(),
          hostState: pendingJournal(moveCloudflareTarget),
        );

        final result = await h.setup.finishSetup();

        expect(result.isRight(), isTrue);
        expect(h.hostStore.stored!.activeHost, PublishHost.github);
        expect(h.hostStore.stored!.pendingMove, isNotNull);
      },
    );

    test('a different Worker is refused before host activation', () async {
      final other = CloudflarePublishTarget.create(
        accountId: cloudflareTestAccountId,
        workerName: 'another-worker',
        accountSubdomain: 'library',
      )!;
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(),
        hostState: pendingJournal(other),
      );

      final result = await h.setup.finishSetup();

      final failure = result.swap().toNullable()!;
      expect(
        (failure as ValidationFailure).message,
        MoveSiteMessages.targetMismatch,
      );
      expect(h.hostStore.saves, 0);
    });
  });

  group('M3 — a proven address is never re-verified destructively', () {
    PublishHostState provenJournal(CloudflarePublishTarget target) =>
        PublishHostState(
          activeHost: PublishHost.cloudflare,
          verifiedTarget: target,
        );

    test(
      'rotating the token onto the verified target deploys nothing',
      () async {
        final h = CloudflareSetupHarness(
          // A fresh record after a token rotation: the account and a MANUAL
          // subdomain, no Worker yet, so the old flow would run the marker-only
          // verification deploy over the live site.
          connection: cloudflareTestConnection(
            withWorker: false,
            confirmed: false,
          ),
          hostState: provenJournal(moveCloudflareTarget),
        );
        h.api.workerExistsValue = true;

        final result = await h.setup.selectWorker('pitak-library');

        final ready = _right(result) as CloudflareWorkerReady;
        expect(ready.target.siteUrl, moveCloudflareTarget.siteUrl);
        expect(
          h.api.deployCalls,
          0,
          reason: 'the journal is the address proof',
        );
        expect(ready.workersWriteConfirmed, isFalse);
        expect(h.hostStore.stored!.activeHost, PublishHost.cloudflare);
      },
    );

    test('the pending move destination is proven the same way', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(
          withWorker: false,
          confirmed: false,
        ),
        hostState: PublishHostState(
          activeHost: PublishHost.github,
          verifiedTarget: moveGitHubTarget,
        ).beginMove(movePending(oldTarget: moveGitHubTarget)),
      );
      h.api.workerExistsValue = true;

      final result = await h.setup.selectWorker('pitak-library');

      expect(result.isRight(), isTrue);
      expect(h.api.deployCalls, 0);
    });

    test(
      'a different Worker still needs the normal verification flow',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withWorker: false,
            confirmed: false,
          ),
          hostState: provenJournal(moveCloudflareTarget),
        );
        h.api.workerExistsValue = true;

        final result = await h.setup.selectWorker('another-worker');

        expect(_right(result), isA<CloudflareVerificationRequired>());
        expect(h.api.deployCalls, 0);
      },
    );

    test('a missing Worker is not a proven address', () async {
      final h = CloudflareSetupHarness(
        connection: cloudflareTestConnection(
          withWorker: false,
          confirmed: false,
        ),
        hostState: provenJournal(moveCloudflareTarget),
      );
      h.api.workerExistsValue = false;

      final result = await h.setup.selectWorker('pitak-library');

      expect(_right(result), isA<CloudflareVerificationRequired>());
      expect(h.api.deployCalls, 0);
    });

    test(
      'the live-site warning appears when the Worker is the active site',
      () async {
        // Same account and Worker, DIFFERENT subdomain: not proven, so the
        // dialog must say the whole site is replaced (fix-plan M3 step 4).
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(
            withWorker: false,
            confirmed: false,
          ).selectSubdomain(cloudflareTestSubdomain('other'), confirmed: false),
          hostState: provenJournal(moveCloudflareTarget),
        );
        h.api.workerExistsValue = true;

        final result = await h.setup.selectWorker('pitak-library');

        final required = _right(result) as CloudflareVerificationRequired;
        expect(required.isActiveSite, isTrue);
      },
    );

    test(
      'a new token is not saved until an account is chosen (M3 step 3)',
      () async {
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection(),
        );
        final before = h.credentials.record;

        _right(await h.setup.begin(cloudflareTestToken()));

        expect(h.credentials.saves, isEmpty);
        expect(h.credentials.record, same(before));
      },
    );
  });

  group('M5 — the pending-move rule runs before any save or remote write', () {
    PublishHostState pendingJournal(CloudflarePublishTarget destination) =>
        PublishHostState(
          activeHost: PublishHost.github,
          verifiedTarget: moveGitHubTarget,
        ).beginMove(
          movePending(oldTarget: moveGitHubTarget, newTarget: destination),
        )!;

    CloudflareSetupHarness harnessFor(CloudflarePublishTarget destination) =>
        CloudflareSetupHarness(
          connection: cloudflareTestConnection(),
          hostState: pendingJournal(destination),
        );

    test('a different account writes nothing and calls nothing', () async {
      final h = harnessFor(moveCloudflareTarget);
      final saves = h.credentials.saves.length;
      final lists = h.api.listCalls;

      final result = await h.setup.selectAccount(
        accountId: CloudflareAccountId.tryParse('f' * 32)!,
        accountName: 'Other',
        pendingToken: cloudflareTestToken(),
      );

      final failure = result.swap().toNullable()!;
      expect(
        (failure as ValidationFailure).message,
        MoveSiteMessages.targetMismatch,
      );
      expect(h.credentials.saves.length, saves);
      expect(h.api.listCalls, lists);
      expect(h.api.accountVerifyCalls, 0);
    });

    test('a different manual Account ID writes nothing', () async {
      final h = harnessFor(moveCloudflareTarget);
      final saves = h.credentials.saves.length;

      final result = await h.setup.selectAccountId(
        'f' * 32,
        pendingToken: cloudflareTestToken(),
      );

      expect(result.isLeft(), isTrue);
      expect(h.credentials.saves.length, saves);
    });

    test('a different manual subdomain writes nothing', () async {
      final h = harnessFor(moveCloudflareTarget);
      final saves = h.credentials.saves.length;

      final result = await h.setup.useManualSubdomain('other-subdomain');

      final failure = result.swap().toNullable()!;
      expect(
        (failure as ValidationFailure).message,
        MoveSiteMessages.targetMismatch,
      );
      expect(h.credentials.saves.length, saves);
    });

    test('creating a different subdomain writes nothing', () async {
      final h = harnessFor(moveCloudflareTarget);
      final saves = h.credentials.saves.length;

      final result = await h.setup.createSubdomain('other-subdomain');

      expect(result.isLeft(), isTrue);
      expect(h.credentials.saves.length, saves);
      expect(h.api.subdomainCreateCalls, 0);
    });

    test(
      'a different Worker is refused before any remote read or write',
      () async {
        final h = harnessFor(moveCloudflareTarget);
        final saves = h.credentials.saves.length;

        final result = await h.setup.selectWorker('another-worker');

        final failure = result.swap().toNullable()!;
        expect(
          (failure as ValidationFailure).message,
          MoveSiteMessages.targetMismatch,
        );
        expect(h.credentials.saves.length, saves);
        expect(h.api.workerExistsCalls, 0);
      },
    );

    test('the exact pending Worker is allowed', () async {
      final h = harnessFor(moveCloudflareTarget);

      final result = await h.setup.selectWorker('pitak-library');

      expect(result.isRight(), isTrue);
    });

    test(
      'the old endpoint is re-authorized read-only, never deployed to',
      () async {
        // Cloudflare is the SOURCE here, so the journal's verified target is
        // the old Worker: setup may re-authorize it, but a verification deploy
        // would overwrite the site the move is about to retire (M5 step 3).
        final pending = movePending(oldTarget: moveCloudflareTarget);
        final h = CloudflareSetupHarness(
          connection: cloudflareTestConnection().selectSubdomain(
            CloudflareSubdomain.tryParse('library')!,
            confirmed: false,
          ),
          hostState: PublishHostState(
            activeHost: PublishHost.cloudflare,
            verifiedTarget: moveCloudflareTarget,
          ).beginMove(pending),
        );
        h.api.workerExistsValue = true;

        final result = await h.setup.selectWorker('pitak-library');

        expect(result.isRight(), isTrue);
        expect(h.api.deployCalls, 0, reason: 'no verification deploy');
        expect(
          h.credentials.record?.status.workersWriteConfirmed,
          isFalse,
          reason: 'write access is still unproven',
        );
      },
    );
  });
}
