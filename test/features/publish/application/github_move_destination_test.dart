import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/github_move_destination.dart';
import 'package:pitaka/features/publish/application/github_move_reader.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/application/site/complete_snapshot_verifier.dart';
import 'package:pitaka/features/publish/application/site/events_section_builder.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../support/cloudflare_s8_fakes.dart';
import '../support/in_memory_github_artifact_store.dart';
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
      itemKeys: const PublishItemKeys(_FixedSalt()),
      catalogue: CatalogueSectionBuilder(
        covers: PublishCoverDecider(
          readLocalCover: (_) async => null,
          fetchRemoteCover: (_) async => null,
        ),
        buildViewerHtml:
            ({
              required libraryName,
              required contact,
              required sharing,
            }) async => utf8.encode('<html>viewer</html>'),
        encodeBooksJson: encodeBooksJsonBytes,
      ),
      events: EventsSectionBuilder(
        readPoster: (_) async => null,
        buildEventsHtml: ({required libraryName, required posters}) async =>
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
      // The move builds through a per-operation spool; the in-memory fake
      // keeps this suite free of file IO while exercising the same seam.
      artifactStores: MemoryGitHubArtifactStore.new,
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
    api.onCommit = (files) async {
      for (final file in files) {
        // Spooled entries carry only metadata; resolve them the way the real
        // commit writer does (review finding 6).
        final bytes = await file.resolveBytes();
        reader.body(file.path, bytes!);
      }
    };

    final result = await destination.publish(
      confirmation: confirmation,
      beforeWrite: () async => true,
    );

    final mismatched = <String>[];
    for (final file in api.commits.single.files) {
      final outcome = reader.outcomes[file.path];
      if (outcome is! PublishedSiteReadBody ||
          GitBlobSha.of(outcome.bytes) != file.gitSha) {
        mismatched.add(file.path);
      }
    }
    expect(mismatched, isEmpty);
    expect(
      result,
      isA<MoveDestinationPublished>(),
      reason: result is MoveDestinationFailed ? result.reason : null,
    );
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
    // The move wrote this phone's keyed catalogue (ADR 0019 Decision 7b).
    expect(destinationManifest.value.catalogueKeyed, isTrue);
    // A later pre-check proves this commit through books.json (Decision 10).
    expect(destinationManifest.value.proofPath, PublishProofPath.booksJson);
    // Plan SP1: the record keeps when GitHub accepted the move's commit.
    expect(destinationManifest.value.committedAt, 1700000000000);
    // The lane is off in this build, so the new site gets no availability.
    expect(
      commit.files.map((file) => file.path),
      isNot(contains('availability.json')),
    );
  });

  test('a lane-on move carries availability.json to the new site '
      '(AV18)', () async {
    reads
      ..availabilityRequest = const AvailabilityFromLoanCounts()
      ..books = const [CatalogueItem(id: 1, title: 'Lent')]
      ..counts = const {1: 1};
    final prepared = await destination.prepare(
      oldTarget: moveCloudflareTarget,
      newTarget: moveGitHubTarget,
      sourceAnchor: moveAnchor(moveCloudflareTarget),
    );
    api.onCommit = (files) async {
      for (final file in files) {
        // Spooled entries carry only metadata; resolve them the way the real
        // commit writer does (review finding 6).
        final bytes = await file.resolveBytes();
        reader.body(file.path, bytes!);
      }
    };

    final result = await destination.publish(
      confirmation: prepared.toNullable()!,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationPublished>());
    final paths = api.commits.single.files.map((file) => file.path);
    expect(paths, contains('availability.json'));
    expect(destinationManifest.value.shaFor('availability.json'), isNotNull);
    expect(destinationManifest.value.catalogueKeyed, isTrue);
  });

  test('a move to a repository that already holds some of the bytes sends '
      'only the rest, deletes nothing foreign and claims nothing foreign '
      '(CV5, ADR 0020 Decision 6)', () async {
    final viewer = GitBlobSha.of(utf8.encode('<html>viewer</html>'));
    api.tree = GitHubTreeSnapshot(
      repo: 'me/library',
      branch: 'main',
      headSha: _head,
      files: {'README.md': 'readme-sha', 'old-site/index.html': viewer},
      truncated: false,
    );
    final prepared = await destination.prepare(
      oldTarget: moveCloudflareTarget,
      newTarget: moveGitHubTarget,
      sourceAnchor: moveAnchor(moveCloudflareTarget),
    );
    // `index.html` is already held at another path, so the commit NAMES it and
    // never resolves its bytes (review finding 6); the live site still serves
    // it, which is what the read-back sees.
    reader.body('index.html', utf8.encode('<html>viewer</html>'));
    api.onCommit = (files) async {
      for (final file in files) {
        final bytes = await file.resolveBytes();
        if (bytes != null) reader.body(file.path, bytes);
      }
    };

    final result = await destination.publish(
      confirmation: prepared.toNullable()!,
      beforeWrite: () async => true,
    );

    expect(result, isA<MoveDestinationPublished>());
    final commit = api.commits.single;
    final byPath = {for (final f in commit.files) f.path: f};
    expect(byPath['index.html']!.gitSha, viewer);
    expect(byPath['index.html']!.upload, isFalse, reason: 'already held');
    expect(byPath['books.json']!.upload, isTrue);
    expect(commit.deletes, isEmpty);
    expect(destinationManifest.value.shaFor('old-site/index.html'), isNull);
    expect(destinationManifest.value.shaFor('index.html'), viewer);
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

  test("J8: a move stopped by GitHub's rate limit says how far it got and "
      'to move again later; nothing is recorded', () async {
    final prepared = await destination.prepare(
      oldTarget: moveCloudflareTarget,
      newTarget: moveGitHubTarget,
      sourceAnchor: moveAnchor(moveCloudflareTarget),
    );
    const limited = PublishCommitRateLimited(
      filesHeld: 120,
      filesToSend: 600,
      wait: Duration(minutes: 1),
      refusedNow: true,
    );
    api.commitResult = limited;

    final result = await destination.publish(
      confirmation: prepared.toNullable()!,
      beforeWrite: () async => true,
    );

    final failure = result as MoveDestinationFailed;
    expect(
      failure.reason,
      gitHubRateLimitedMessage(limited, operation: GitHubLimitedOperation.move),
    );
    expect(failure.reason, contains('120 of 600 files'));
    expect(destinationManifest.saves, 0);
  });

  test(
    'a failed commit record is reported with the failed read-back (L12)',
    () async {
      final prepared = await destination.prepare(
        oldTarget: moveCloudflareTarget,
        newTarget: moveGitHubTarget,
        sourceAnchor: moveAnchor(moveCloudflareTarget),
      );
      // The commit lands, but its local record cannot be saved and read-back
      // fails (no bodies are served).
      destinationManifest.failSave = true;

      final result = await destination.publish(
        confirmation: prepared.toNullable()!,
        beforeWrite: () async => true,
      );

      final failure = result as MoveDestinationFailed;
      expect(failure.reason, contains(MoveSiteMessages.localRecordNotSaved));
      expect(failure.localStateSaved, isFalse);
      expect(api.commits, hasLength(1));
    },
  );

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
      // The commit landed, so the copy says so and that Pages may still be
      // building — never a bare "could not be verified" (handoff §12).
      expect(failure.reason, MoveSiteMessages.gitHubDestinationNotLiveYet);
      expect(failure.reason, contains('copied to the new GitHub Pages site'));
      expect(failure.reason, contains('10 minutes'));
      expect(failure.reason, contains('Your current site was not changed.'));
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
      api.onCommit = (files) async {
        for (final file in files) {
          final bytes = await file.resolveBytes();
          reader.body(file.path, bytes!);
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
  Future<void> Function(List<DesiredFile> files)? onCommit;
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
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async => tree.headSha;

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) async => tree;

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required GitHubCommitPlan plan,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
    Future<void> Function(String gitSha)? onBlobStored,
  }) async {
    final files = plan.files;
    commits.add((
      files: files,
      deletes: deletePaths,
      expectedHead: expectedHead,
      branch: branch,
    ));
    await onCommit?.call(files);
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
