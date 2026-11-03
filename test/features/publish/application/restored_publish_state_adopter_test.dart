import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/restored_publish_state_adopter.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../support/availability_lane_fakes.dart';
import '../support/cloudflare_fakes.dart';
import '../support/publish_state_fixtures.dart';

/// Adopting a restored backup's publishing record (plan CV7, S11): inside
/// the publish queue through the keys guard, only on a phone that has not
/// published, with `catalogueKeyed` cleared, and undone completely when any
/// write fails (fail closed).
void main() {
  late MemoryKeysReset keys;
  late _Salt salt;
  late FakePublishHostStateStore journal;
  late _GitHubSignIn gitHubSignIn;
  late InMemoryCloudflareCredentialStore cloudflareSignIn;

  setUp(() {
    keys = MemoryKeysReset();
    salt = _Salt(phoneSalt);
    journal = FakePublishHostStateStore();
    gitHubSignIn = _GitHubSignIn();
    cloudflareSignIn = InMemoryCloudflareCredentialStore();
  });

  RestoredPublishStateAdopter adopter() => RestoredPublishStateAdopter(
    salt: salt,
    gitHubRecord: keys.gitHub,
    cloudflareRecord: keys.cloudflare,
    hostState: PublishHostStateRepository(
      store: journal,
      manifest: keys.gitHub,
      verifier: FakePublishedSiteVerifier(),
    ),
    gitHubCredentials: gitHubSignIn,
    cloudflareCredentials: cloudflareSignIn,
    keysChangeGuard: keys.reset.beforeIdsChange,
  );

  void expectPhoneUnchanged({List<int>? saltNow}) {
    expect(salt.current, saltNow ?? phoneSalt);
    expect(keys.gitHub.current.repo, isNull);
    expect(keys.cloudflare.current.target, isNull);
    expect(journal.stored, isNull);
  }

  group('a phone that has not published adopts', () {
    test('salt, both records (keys not vouched for) and the journal', () async {
      final archived = archivedState();
      final outcome = await adopter().adoptRestored(archived);

      expect(outcome, PublishStateRestoreOutcome.adopted);
      expect(salt.current, archiveSalt);

      final gitHub = keys.gitHub.current;
      expect(gitHub.repo, 'degt3rt/my-library');
      expect(gitHub.fileShas, archived.gitHubRecord.fileShas);
      expect(gitHub.coverUrlByBookId, archived.gitHubRecord.coverUrlByBookId);
      expect(gitHub.coverRendition, archived.gitHubRecord.coverRendition);
      expect(gitHub.headSha, archived.gitHubRecord.headSha);
      expect(gitHub.state, archived.gitHubRecord.state);
      expect(gitHub.catalogueKeyed, isFalse);
      // Plan SP4: another phone's record is checked against the tree before
      // a publish trusts it, even at the same head.
      expect(gitHub.adoptedFromBackup, isTrue);
      expect(archived.gitHubRecord.adoptedFromBackup, isFalse);
      expect(
        gitHub.reconciledAtUnchangedHead(
          ownerRepo: gitHub.repo!,
          branch: gitHub.branch!,
          headSha: gitHub.headSha!,
        ),
        isNull,
      );

      final cloudflare = keys.cloudflare.current;
      expect(cloudflare.describes(archiveCloudflare), isTrue);
      expect(cloudflare.files.keys, archived.cloudflareRecord.files.keys);
      expect(cloudflare.catalogueKeyed, isFalse);
      expect(keys.cloudflare.pending.target, isNull, reason: 'never adopted');

      expect(journal.stored!.activeHost, PublishHost.github);
      expect(
        journal.stored!.verifiedTarget!.isSameExactTarget(archiveGitHub),
        isTrue,
      );
      expect(journal.stored!.pendingMove, isNull);
    });

    test('the availability lane is told the keys changed', () async {
      await adopter().adoptRestored(archivedState());
      expect(keys.idsChanged, 1);
    });

    test(
      'it waits for the publish queue (no publish runs in between)',
      () async {
        final running = Completer<void>();
        final publish = keys.queue.enqueue(() => running.future);
        final adoption = adopter().adoptRestored(archivedState());
        await pumpEventQueue();
        expect(salt.current, phoneSalt, reason: 'still waiting for the queue');
        running.complete();
        await publish;
        expect(await adoption, PublishStateRestoreOutcome.adopted);
        expect(salt.current, archiveSalt);
      },
    );

    test('connected to the backup site but never published there', () async {
      gitHubSignIn.repo = 'degt3rt/my-library';
      journal.stored = const PublishHostState(activeHost: PublishHost.github);
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.adopted);
      expect(journal.stored!.verifiedTarget, isNotNull);
    });

    test('a backup without a journal host writes no journal', () async {
      final outcome = await adopter().adoptRestored(
        archivedState(activeHost: null, verifiedGitHub: false),
      );
      expect(outcome, PublishStateRestoreOutcome.adopted);
      expect(journal.saves, 0);
      expect(keys.gitHub.current.repo, 'degt3rt/my-library');
    });

    test('a backup without a Cloudflare record leaves it untouched', () async {
      final archived = PublishStateBackup.tryCreate(
        coverSalt: archiveSalt,
        gitHubRecord: gitHubRecord(),
        activeHost: PublishHost.github,
        verifiedTarget: archiveGitHub,
      )!;
      expect(
        await adopter().adoptRestored(archived),
        PublishStateRestoreOutcome.adopted,
      );
      expect(keys.cloudflare.saves, isEmpty);
    });
  });

  group('a phone with its own publishing keeps it', () {
    test('it published to GitHub (even the same repository)', () async {
      keys.gitHub.current = gitHubRecord(keyed: false);
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.keptThisPhone);
      expect(salt.current, phoneSalt);
      expect(salt.replaces, 0);
      expect(journal.saves, 0);
    });

    test('it proved a site', () async {
      journal.stored = PublishHostState(
        activeHost: PublishHost.github,
        verifiedTarget: archiveGitHub,
      );
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.keptThisPhone);
      expect(salt.replaces, 0);
    });

    test('it is connected to another site', () async {
      gitHubSignIn.repo = 'me/another-site';
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.keptThisPhone);
      expectPhoneUnchanged();
    });

    test('its Cloudflare connection is not the backup active site', () async {
      cloudflareSignIn.record = cloudflareTestConnection();
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.keptThisPhone);
      expectPhoneUnchanged();
    });
  });

  group('this phone state cannot be read: nothing is applied', () {
    test('an unreadable journal', () async {
      journal.unreadable = true;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expect(salt.replaces, 0);
      expect(keys.gitHub.saves, isEmpty);
    });

    test('an unreadable Cloudflare connection', () async {
      cloudflareSignIn.failRead = true;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expectPhoneUnchanged();
    });

    test('a GitHub sign-in read that throws', () async {
      gitHubSignIn.throws = true;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expectPhoneUnchanged();
    });

    test('a salt read that throws (before any write)', () async {
      salt.readThrows = true;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expect(salt.replaces, 0);
      expect(keys.gitHub.saves, isEmpty);
    });

    test('the keys guard refuses (the lane store cannot be saved)', () async {
      keys.laneStore.failWrites = true;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expectPhoneUnchanged();
      expect(keys.idsChanged, 0);
    });
  });

  group('a failed write is undone in reverse order (fail closed)', () {
    test('the salt cannot be replaced: nothing else is written', () async {
      salt.failReplaceAt = 1;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expectPhoneUnchanged();
    });

    test('the GitHub record cannot be saved: the salt is put back', () async {
      keys.gitHub.saveFails = true;
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      expect(salt.current, phoneSalt);
      expect(salt.replaces, 2);
      expect(keys.cloudflare.saves, isEmpty);
      expect(journal.saves, 0);
    });

    test(
      'the Cloudflare record cannot be saved: GitHub and salt put back',
      () async {
        keys.cloudflare.failSave = true;
        final outcome = await adopter().adoptRestored(archivedState());
        expect(outcome, PublishStateRestoreOutcome.notApplied);
        expect(salt.current, phoneSalt);
        expect(keys.gitHub.current, same(PublishManifest.empty));
        expect(journal.saves, 0);
      },
    );

    test(
      'the journal cannot be saved: every record and the salt put back',
      () async {
        journal.failSave = true;
        final outcome = await adopter().adoptRestored(archivedState());
        expect(outcome, PublishStateRestoreOutcome.notApplied);
        expect(salt.current, phoneSalt);
        expect(keys.gitHub.current, same(PublishManifest.empty));
        expect(keys.cloudflare.current, same(CloudflareSiteManifest.empty));
        expect(journal.stored, isNull);
      },
    );

    test('a failed undo is logged, the outcome stays "not applied"', () async {
      keys.gitHub.saveFails = true;
      salt.failReplaceAt = 2; // the undo's replace
      final outcome = await adopter().adoptRestored(archivedState());
      expect(outcome, PublishStateRestoreOutcome.notApplied);
      // The archive's salt stayed: harmless (the records are empty, so the
      // next publish only costs uploads), and the log says so.
      expect(salt.current, archiveSalt);
    });
  });

  test('the journal write re-checks the rule at the repository', () async {
    // The adoption rule already refused this, but the repository refuses on
    // its own too: a verified address is never overwritten from a backup.
    final repository = PublishHostStateRepository(
      store: FakePublishHostStateStore(
        PublishHostState(
          activeHost: PublishHost.github,
          verifiedTarget: GitHubPublishTarget.create('me/mine'),
        ),
      ),
      manifest: keys.gitHub,
      verifier: FakePublishedSiteVerifier(),
    );
    final result = await repository.adoptFromBackup(
      activeHost: PublishHost.github,
      verifiedTarget: archiveGitHub,
    );
    expect(result.isLeft(), isTrue);
  });
}

/// The replaceable salt in memory.
final class _Salt implements ReplaceablePublishCoverSaltStore {
  _Salt(List<int> initial) : current = List.of(initial);

  List<int> current;
  int replaces = 0;
  int failReplaceAt = -1;
  bool readThrows = false;

  @override
  Future<List<int>> salt() async {
    if (readThrows) throw StateError('secure storage');
    return current;
  }

  @override
  Future<Either<Failure, Unit>> replace(List<int> salt) async {
    replaces++;
    if (replaces == failReplaceAt) {
      return left(const StorageFailure('synthetic salt write'));
    }
    current = List.of(salt);
    return right(unit);
  }
}

/// The GitHub sign-in's repository; no token is ever involved.
final class _GitHubSignIn implements PublishCredentialReader {
  String? repo;
  bool throws = false;

  @override
  Future<String?> targetRepo() async {
    if (throws) throw StateError('secure storage');
    return repo;
  }

  @override
  Future<String?> token() => throw UnimplementedError('never read');
}
