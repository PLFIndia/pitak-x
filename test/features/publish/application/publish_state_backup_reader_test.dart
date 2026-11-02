import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_state_backup_reader.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

import '../support/cloudflare_fakes.dart';
import '../support/cloudflare_s8_fakes.dart';
import '../support/github_lane_fakes.dart';
import '../support/move_fakes.dart';
import '../support/publish_state_fixtures.dart';

/// What a backup takes from this phone (plan CV6, S11): the salt, both
/// records and the journal's host and verified address — nothing when the
/// phone published nothing, and never a credential.
void main() {
  late _Salt salt;
  late LaneMemManifest gitHub;
  late InMemoryCloudflareManifestStore cloudflare;
  late FakePublishHostStateStore journal;

  setUp(() {
    salt = _Salt();
    gitHub = LaneMemManifest();
    cloudflare = InMemoryCloudflareManifestStore();
    journal = FakePublishHostStateStore();
  });

  PublishStateBackupReader reader() => PublishStateBackupReader(
    salt: salt,
    gitHubRecord: gitHub,
    cloudflareRecord: cloudflare,
    hostState: PublishHostStateRepository(
      store: journal,
      manifest: gitHub,
      verifier: FakePublishedSiteVerifier(),
    ),
  );

  test('a phone that published nothing carries nothing, and reads no salt '
      '(none is created by a backup)', () async {
    journal.stored = const PublishHostState(activeHost: PublishHost.cloudflare);
    final result = await reader().forBackup();
    expect(result.getOrElse((f) => fail('$f')), isNull);
    expect(salt.reads, 0);
  });

  test('a GitHub publisher carries salt, record and journal facts', () async {
    gitHub.current = gitHubRecord();
    journal.stored = PublishHostState(
      activeHost: PublishHost.github,
      verifiedTarget: archiveGitHub,
    );
    final state = (await reader().forBackup()).getOrElse((f) => fail('$f'))!;
    expect(state.coverSalt, archiveSalt);
    expect(state.gitHubRecord, same(gitHub.current));
    expect(state.cloudflareRecord.target, isNull);
    expect(state.activeHost, PublishHost.github);
    expect(state.verifiedTarget!.isSameExactTarget(archiveGitHub), isTrue);
  });

  test('a Cloudflare record alone is carried (no journal)', () async {
    cloudflare.current = cloudflareRecord();
    final state = (await reader().forBackup()).getOrElse((f) => fail('$f'))!;
    expect(state.cloudflareRecord.describes(archiveCloudflare), isTrue);
    expect(state.activeHost, isNull);
  });

  test('a pending move is never carried; its old site is', () async {
    final pending = movePending();
    gitHub.current = gitHubRecord();
    journal.stored = PublishHostState(
      activeHost: pending.oldTarget.host,
      verifiedTarget: pending.oldTarget,
      pendingMove: pending,
    );
    final state = (await reader().forBackup()).getOrElse((f) => fail('$f'))!;
    expect(state.verifiedTarget!.isSameExactTarget(pending.oldTarget), isTrue);
  });

  test('a legacy GitHub record without a repository is left out', () async {
    gitHub.current = PublishManifest(fileShas: {'books.json': sha40('a')});
    expect((await reader().forBackup()).getOrElse((f) => fail('$f')), isNull);
    cloudflare.current = cloudflareRecord();
    final state = (await reader().forBackup()).getOrElse((f) => fail('$f'))!;
    expect(state.gitHubRecord, same(PublishManifest.empty));
  });

  test('an unreadable journal is a Left (the backup says so)', () async {
    gitHub.current = gitHubRecord();
    journal.unreadable = true;
    expect((await reader().forBackup()).isLeft(), isTrue);
  });

  test('a salt read that throws is a Left, never a throw', () async {
    gitHub.current = gitHubRecord();
    salt.throws = true;
    expect((await reader().forBackup()).isLeft(), isTrue);
  });

  test('a damaged salt (wrong length) is a Left', () async {
    gitHub.current = gitHubRecord();
    salt.value = const [1, 2, 3];
    expect((await reader().forBackup()).isLeft(), isTrue);
  });

  test('the reader cannot reach a credential: it imports no credential '
      'store and takes none', () {
    final code = File(
      'lib/features/publish/application/site/publish_state_backup_reader.dart',
    ).readAsLinesSync().where((line) => !line.trimLeft().startsWith('///'));
    expect(code.where((line) => line.contains('redential')), isEmpty);
  });
}

final class _Salt implements PublishCoverSaltStore {
  List<int> value = archiveSalt;
  int reads = 0;
  bool throws = false;

  @override
  Future<List<int>> salt() async {
    reads++;
    if (throws) throw StateError('secure storage');
    return value;
  }
}
