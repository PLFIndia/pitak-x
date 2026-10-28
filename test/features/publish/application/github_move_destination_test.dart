import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/github_move_destination.dart';
import 'package:pitaka/features/publish/application/github_move_reader.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/complete_snapshot_verifier.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

import '../support/cloudflare_s8_fakes.dart';
import '../support/move_fakes.dart';

const _token = 'synthetic-token-never-printed';
const _head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late _FakeDestinationApi api;
  late MemoryManifest destinationManifest;
  late FakeS8Reads reads;
  late FakeStructuredReader reader;
  late GitHubMoveDestination destination;

  GitHubMoveReader moveReader() => GitHubMoveReader(
    api: api,
    credentials: _DestinationCreds(),
    manifest: destinationManifest,
  );

  setUp(() {
    api = _FakeDestinationApi();
    destinationManifest = MemoryManifest();
    reads = FakeS8Reads();
    reader = FakeStructuredReader();
    final builder = PublishSnapshotBuilder(
      catalogue: CatalogueSectionBuilder(
        covers: PublishCoverDecider(
          coverIds: const PublishCoverIds(_FixedSalt()),
          readLocalCover: (_) async => null,
          fetchRemoteCover: (_) async => null,
        ),
        buildViewerHtml: () async => utf8.encode('<html>viewer</html>'),
        encodeBooksJson: encodeBooksJsonBytes,
      ),
      events: EventsSectionBuilder(
        readPoster: (_) async => null,
        buildEventsHtml: (posters) async =>
            utf8.encode('<html>${posters.length}</html>'),
        buildEventsJson: (posters) => utf8.encode('{"posters":[]}'),
      ),
    );
    destination = GitHubMoveDestination(
      reader: moveReader(),
      api: api,
      manifest: destinationManifest,
      snapshotBuilder: builder,
      reads: reads,
      verifier: CompleteSnapshotVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 1,
      ),
      clock: () => 1700000000000,
    );
  });

  test(
    'prepare is write-free and returns a complete reviewed snapshot',
    () async {
      final result = await destination.prepare(
        oldTarget: moveCloudflareTarget,
        newTarget: moveGitHubTarget,
        sourceAnchor: moveAnchor(moveCloudflareTarget),
      );

      final confirmation = result.getOrElse(
        (f) => fail('expected success, got $f'),
      );
      expect(
        confirmation.newTarget.isSameExactTarget(moveGitHubTarget),
        isTrue,
      );
      expect(confirmation.digest, isNotEmpty);
      expect(confirmation.catalogueItemCount, 0);
      expect(confirmation.posterCount, 0);
      expect(api.commits, isEmpty);
      expect(reader.calls, isEmpty);
      expect(destinationManifest.saves, 0);
    },
  );

  test('publish commits one complete snapshot, verifies it, then records it '
      'live', () async {
    final prepared = await destination.prepare(
      oldTarget: moveCloudflareTarget,
      newTarget: moveGitHubTarget,
      sourceAnchor: moveAnchor(moveCloudflareTarget),
    );
    final confirmation = prepared.getOrElse(
      (f) => fail('expected success, got $f'),
    );
    api.onCommit = (files) {
      for (final file in files) {
        reader.body(file.path, file.bytes);
      }
    };

    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationPublished>());
    expect((result as MoveDestinationPublished).localStateSaved, isTrue);
    expect(api.commits, hasLength(1));
    final commit = api.commits.single;
    expect(commit.expectedHead, _head);
    expect(commit.branch, 'main');
    expect(commit.files.map((file) => file.path), contains('index.html'));
    expect(commit.files.map((file) => file.path), contains('books.json'));
    expect(commit.deletes, isEmpty);
    expect(destinationManifest.value.state, PublishState.live);
    expect(destinationManifest.value.headSha, 'commit-1');
    // One save records the accepted commit, the second records read-back.
    expect(destinationManifest.saves, 2);
  });

  test('a digest mismatch re-prompts before any destination write', () async {
    final prepared = await destination.prepare(
      oldTarget: moveCloudflareTarget,
      newTarget: moveGitHubTarget,
      sourceAnchor: moveAnchor(moveCloudflareTarget),
    );
    final stale = MoveSiteConfirmation(
      oldTarget: prepared.toNullable()!.oldTarget,
      newTarget: prepared.toNullable()!.newTarget,
      sourceAnchor: prepared.toNullable()!.sourceAnchor,
      digest: 'different-digest',
      catalogueItemCount: 0,
      posterCount: 0,
      availabilityOmitted: false,
    );

    final result = await destination.publish(
      confirmation: stale,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationConfirmationRequired>());
    expect(api.commits, isEmpty);
    expect(destinationManifest.saves, 0);
  });

  test(
    'a source that changed immediately before the write aborts it',
    () async {
      final prepared = await destination.prepare(
        oldTarget: moveCloudflareTarget,
        newTarget: moveGitHubTarget,
        sourceAnchor: moveAnchor(moveCloudflareTarget),
      );
      final confirmation = prepared.toNullable()!;

      final result = await destination.publish(
        confirmation: confirmation,
        beforeWrite: () async => false,
      );

      final failure = result as MoveDestinationFailed;
      expect(failure.reason, MoveSiteMessages.sourceChanged);
      expect(api.commits, isEmpty);
      expect(destinationManifest.saves, 0);
    },
  );

  test('a stale expected head never overwrites a newer destination', () async {
    final prepared = await destination.prepare(
      oldTarget: moveCloudflareTarget,
      newTarget: moveGitHubTarget,
      sourceAnchor: moveAnchor(moveCloudflareTarget),
    );
    api.commitResult = const PublishCommitStale();

    final result = await destination.publish(
      confirmation: prepared.toNullable()!,
      beforeWrite: () async => true,
    );

    final failure = result as MoveDestinationFailed;
    expect(failure.reason, MoveSiteMessages.stale);
    expect(destinationManifest.saves, 0);
  });

  test(
    'failed destination read-back reports the truth and is not recorded',
    () async {
      final prepared = await destination.prepare(
        oldTarget: moveCloudflareTarget,
        newTarget: moveGitHubTarget,
        sourceAnchor: moveAnchor(moveCloudflareTarget),
      );
      // Leave the public site stale: no bodies served.
      final result = await destination.publish(
        confirmation: prepared.toNullable()!,
        beforeWrite: () async => true,
      );

      final failure = result as MoveDestinationFailed;
      expect(failure.reason, MoveSiteMessages.destinationNotVerified);
      expect(destinationManifest.value.state, isNot(PublishState.live));
    },
  );

  test(
    'an already-committed destination is verified without a second commit',
    () async {
      final prepared = await destination.prepare(
        oldTarget: moveCloudflareTarget,
        newTarget: moveGitHubTarget,
        sourceAnchor: moveAnchor(moveCloudflareTarget),
      );
      final confirmation = prepared.toNullable()!;
      api.onCommit = (files) {
        for (final file in files) {
          reader.body(file.path, file.bytes);
        }
      };
      await destination.publish(
        confirmation: confirmation,
        beforeWrite: () async => true,
      );
      final commitsAfterFirst = api.commits.length;

      // The retry sees the exact committed tree and local record.
      api.tree = GitHubTreeSnapshot(
        repo: 'me/library',
        branch: 'main',
        headSha: destinationManifest.value.headSha!,
        files: destinationManifest.value.fileShas,
        truncated: false,
      );

      final retried = await destination.publish(
        confirmation: confirmation,
        beforeWrite: () async => true,
      );

      expect(retried, isA<MoveDestinationPublished>());
      expect(api.commits, hasLength(commitsAfterFirst));
    },
  );
}

const _pages = PagesSite(
  sourceBranch: 'main',
  sourcePath: '/',
  isWorkflowBuild: false,
);

final class _FakeDestinationApi implements GitHubGitDataApi {
  GitHubTreeSnapshot tree = const GitHubTreeSnapshot(
    repo: 'me/library',
    branch: 'main',
    headSha: _head,
    files: {},
    truncated: false,
  );
  PublishCommitResult commitResult = const PublishCommitSuccess('commit-1', []);
  void Function(List<DesiredFile> files)? onCommit;
  final List<
    ({
      List<DesiredFile> files,
      List<String> deletes,
      String expectedHead,
      String branch,
    })
  >
  commits = [];

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async => _pages;

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async => tree;

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
  }) async {
    commits.add((
      files: files,
      deletes: deletePaths,
      expectedHead: expectedHead,
      branch: branch,
    ));
    onCommit?.call(files);
    return commitResult;
  }
}

final class _DestinationCreds implements PublishCredentialStore {
  @override
  Future<String?> token() async => _token;

  @override
  Future<String?> targetRepo() async => 'me/library';

  @override
  Future<void> setToken(String value) async {}

  @override
  Future<void> clearToken() async {}

  @override
  Future<void> setTargetRepo(String value) async {}

  @override
  Future<void> clearTargetRepo() async {}
}

final class _FixedSalt implements PublishCoverSaltStore {
  const _FixedSalt();

  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}
