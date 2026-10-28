import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/move_target_resolver.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../support/cloudflare_fakes.dart';
import '../support/move_fakes.dart';

void main() {
  late ScriptedHostStore store;
  late InMemoryCloudflareCredentialStore cloudflare;
  late _GitHubCreds gitHub;
  late ConfiguredMoveTargetResolver resolver;

  setUp(() {
    store = ScriptedHostStore(
      PublishHostState(
        activeHost: PublishHost.github,
        verifiedTarget: moveGitHubTarget,
      ),
    );
    cloudflare = InMemoryCloudflareCredentialStore(cloudflareTestConnection());
    gitHub = _GitHubCreds();
    resolver = ConfiguredMoveTargetResolver(
      hostState: moveHostRepository(store),
      gitHubCredentials: gitHub,
      cloudflareCredentials: cloudflare,
    );
  });

  test(
    'resolves the verified source and the other host exact target',
    () async {
      final result = await resolver();

      final targets = result.getOrElse((f) => fail('expected success, got $f'));
      expect(targets.oldTarget.targetId, moveGitHubTarget.targetId);
      expect(targets.newTarget.targetId, moveCloudflareTarget.targetId);
    },
  );

  test('a pending move blocks every new move', () async {
    store.stored =
        PublishHostState(
          activeHost: PublishHost.github,
          verifiedTarget: moveGitHubTarget,
        ).beginMove(
          movePending(
            oldTarget: moveGitHubTarget,
            newTarget: moveCloudflareTarget,
          ),
        );

    final result = await resolver();

    final failure = result.swap().toNullable()!;
    expect(
      (failure as ValidationFailure).message,
      MoveSiteMessages.pendingAlreadyExists,
    );
  });

  test('an unreadable journal is never treated as unconfigured', () async {
    store.failLoad = true;

    final result = await resolver();

    final failure = result.swap().toNullable()!;
    expect(failure, isA<StorageFailure>());
  });

  test('a missing destination is a setup instruction, not a guess', () async {
    cloudflare.record = null;

    final result = await resolver();

    final failure = result.swap().toNullable()!;
    expect(
      (failure as ValidationFailure).message,
      MoveSiteMessages.setupRequired,
    );
  });

  test('a credential read failure never substitutes another target', () async {
    cloudflare.failRead = true;

    final result = await resolver();

    final failure = result.swap().toNullable()!;
    expect(
      (failure as ValidationFailure).message,
      MoveSiteMessages.setupRequired,
    );
    expect(cloudflare.reads, 1);
  });

  test('the old target must still be the verified one', () async {
    gitHub.targetRepoValue = 'me/other-library';

    final result = await resolver();

    final failure = result.swap().toNullable()!;
    expect(
      (failure as ValidationFailure).message,
      MoveSiteMessages.setupRequired,
    );
  });
}

final class _GitHubCreds implements PublishCredentialStore {
  String? tokenValue = 'synthetic-token';
  String? targetRepoValue = 'me/library';

  @override
  Future<String?> token() async => tokenValue;

  @override
  Future<String?> targetRepo() async => targetRepoValue;

  @override
  Future<void> setToken(String value) async => tokenValue = value;

  @override
  Future<void> clearToken() async => tokenValue = null;

  @override
  Future<void> setTargetRepo(String value) async => targetRepoValue = value;

  @override
  Future<void> clearTargetRepo() async => targetRepoValue = null;
}
