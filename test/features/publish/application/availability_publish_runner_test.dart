import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

import '../support/cloudflare_s8_fakes.dart';
import '../support/github_lane_fakes.dart';
import '../support/key_set_fixtures.dart';

/// One lane publish inside the publish queue (ADR 0019 Decision 7, plan C.4
/// "When the timer fires"; the stale-file removal of plan S6).
void main() {
  final gitHub = GitHubPublishTarget.create('me/lib')!;
  final cloudflare = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'kadugodi',
  )!;
  final set = AvailabilitySnapshot.tryCreate(
    keySet: testKeySetId,
    keys: const ['0000000000000001'],
    asOfMillis: 60000,
  )!;

  late SerialOpQueue queue;
  late Either<Failure, PublishTarget> target;
  late List<(String, AvailabilityUpdate)> calls;
  late List<AvailabilityPublishResult> results;
  late LaneMemManifest gitHubRecord;
  late InMemoryCloudflareManifestStore cloudflareRecord;
  late bool throwOnPublish;
  Future<Either<Failure, Unit>> Function(PublishTarget target)? checkTarget;

  setUp(() {
    queue = SerialOpQueue();
    target = Right(gitHub);
    calls = [];
    results = [];
    gitHubRecord = LaneMemManifest();
    cloudflareRecord = InMemoryCloudflareManifestStore();
    throwOnPublish = false;
    checkTarget = null;
  });

  Future<AvailabilityPublishResult> answer(
    String host,
    AvailabilityUpdate update,
  ) async {
    calls.add((host, update));
    if (throwOnPublish) throw _ThrownByUseCase();
    return results.isEmpty
        ? const AvailabilityAlreadyPublished()
        : results.removeAt(0);
  }

  AvailabilityPublishRunner runner() => AvailabilityPublishRunner(
    queue: queue,
    resolveTarget: () async => target,
    gitHub: ({required target, required update}) => answer('github', update),
    cloudflare: ({required target, required update}) =>
        answer('cloudflare', update),
    gitHubRecord: gitHubRecord,
    cloudflareRecord: cloudflareRecord,
    checkTarget: checkTarget,
  );

  test("runs the active host's publish and reports its target", () async {
    results.add(const AvailabilityLive(acceptedAt: 1));
    final run =
        await runner()(AvailabilityWrite(set)) as AvailabilityRunFinished;
    expect(run.target, same(gitHub));
    expect(run.result, isA<AvailabilityLive>());
    expect(run.removal, isNull);
    expect(calls.single.$1, 'github');

    target = Right(cloudflare);
    await runner()(AvailabilityWrite(set));
    expect(calls.last.$1, 'cloudflare');
  });

  test('no target (gates a/c): blocked with the fixed sentence, nothing '
      'sent', () async {
    target = const Left(
      ValidationFailure(
        'Finish, skip or cancel the pending move before publishing again.',
      ),
    );
    final run =
        await runner()(AvailabilityWrite(set)) as AvailabilityRunBlocked;
    expect(
      run.reason,
      'Finish, skip or cancel the pending move before publishing again.',
    );
    expect(calls, isEmpty);
    expect((await runner().currentTarget()).getLeft().toNullable(), run.reason);
  });

  group('a removal checks the local record first (R13)', () {
    test('GitHub: nothing recorded → already published, no network', () async {
      final run =
          await runner()(const AvailabilityDelete()) as AvailabilityRunFinished;
      expect(run.result, isA<AvailabilityAlreadyPublished>());
      expect(calls, isEmpty);
    });

    test('GitHub: a record of another repo does not count', () async {
      gitHubRecord.current = const PublishManifest(
        repo: 'me/other',
        fileShas: {'availability.json': 'a1'},
      );
      await runner()(const AvailabilityDelete());
      expect(calls, isEmpty);
    });

    test('GitHub: a recorded file is removed through the use case', () async {
      gitHubRecord.current = const PublishManifest(
        repo: 'me/lib',
        fileShas: {'availability.json': 'a1'},
      );
      await runner()(const AvailabilityDelete());
      expect(calls.single.$2, isA<AvailabilityDelete>());
    });

    test('Cloudflare: the record or the unconfirmed attempt counts', () async {
      target = Right(cloudflare);
      final withFile = CloudflareSiteManifest(
        target: cloudflare,
        publishId: 'a' * 32,
        files: {
          'books.json': _entry(),
          'index.html': _entry(CloudflareContentType.html),
          'pitak-publish.json': _entry(),
          'availability.json': _entry(),
        },
      );
      await runner()(const AvailabilityDelete());
      expect(calls, isEmpty, reason: 'nothing recorded');

      cloudflareRecord.pending = withFile;
      await runner()(const AvailabilityDelete());
      expect(calls, hasLength(1));

      cloudflareRecord
        ..pending = CloudflareSiteManifest.empty
        ..current = withFile;
      await runner()(const AvailabilityDelete());
      expect(calls, hasLength(2));
    });
  });

  test('a "not ready" write with a stale file is followed by its removal in '
      'the same queue turn (plan S6)', () async {
    results
      ..add(
        const AvailabilityNotReady(
          AvailabilityPublishMessages.catalogueNotKeyed,
          staleFileRecorded: true,
        ),
      )
      ..add(const AvailabilityGoingLive(acceptedAt: 2, verification: null));
    var queuedRanAt = -1;
    final run = runner()(AvailabilityWrite(set));
    final other = queue.enqueue(() async => queuedRanAt = calls.length);

    final finished = await run as AvailabilityRunFinished;
    await other;

    expect(finished.result, isA<AvailabilityNotReady>());
    expect(finished.removal, isA<AvailabilityGoingLive>());
    expect(calls.map((c) => c.$2.runtimeType), [
      AvailabilityWrite,
      AvailabilityDelete,
    ]);
    expect(queuedRanAt, 2, reason: 'nothing ran between the two');
  });

  test('a "not ready" write without a stale file sends nothing more', () async {
    results.add(
      const AvailabilityNotReady(AvailabilityPublishMessages.catalogueNotKeyed),
    );
    final run =
        await runner()(AvailabilityWrite(set)) as AvailabilityRunFinished;
    expect(run.removal, isNull);
    expect(calls, hasLength(1));
  });

  test(
    'a refused target check blocks both gateways and a later run retries',
    () async {
      var checks = 0;
      checkTarget = (_) async {
        checks++;
        return left(const ValidationFailure('recovery pending'));
      };

      final blocked = await runner()(AvailabilityWrite(set));

      expect(blocked, isA<AvailabilityRunBlocked>());
      expect((blocked as AvailabilityRunBlocked).reason, 'recovery pending');
      expect(calls, isEmpty);
      expect(gitHubRecord.saves, isEmpty);
      expect(cloudflareRecord.saves, isEmpty);

      checkTarget = (_) async {
        checks++;
        return right(unit);
      };
      results.add(const AvailabilityLive(acceptedAt: 1));
      final retried = await runner()(AvailabilityWrite(set));

      expect(retried, isA<AvailabilityRunFinished>());
      expect(calls.single.$1, 'github');
      expect(checks, 2);
    },
  );

  test('a throwing use case becomes a pending result, never a crash', () async {
    throwOnPublish = true;
    final run =
        await runner()(AvailabilityWrite(set)) as AvailabilityRunFinished;
    expect(
      (run.result as AvailabilityPending).reason,
      AvailabilityPublishRunner.unexpectedMessage,
    );
  });
}

final class _ThrownByUseCase implements Exception {}

CloudflareAssetEntry _entry([
  CloudflareContentType type = CloudflareContentType.json,
]) => CloudflareAssetEntry(sha: 'sha', hash: '0' * 32, size: 10, type: type);
