import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_move_reader.dart';
import 'package:pitaka/features/publish/application/github_move_source.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';

import '../support/cloudflare_s8_fakes.dart';
import '../support/move_fakes.dart';

const _token = 'synthetic-token-never-printed';

const _pages = PagesSite(
  sourceBranch: 'main',
  sourcePath: '/',
  isWorkflowBuild: false,
);

Map<String, String> _shas(Iterable<String> bodies) => {
  for (final body in bodies) body: body,
};

void main() {
  late _FakeGitData gitData;
  late _FakeAdmin admin;
  late _FakeCreds credentials;
  late MemoryManifest manifest;
  late FakeStructuredReader reader;
  late GitHubMoveSource source;
  late GitHubMoveReader moveReader;

  setUp(() {
    gitData = _FakeGitData();
    admin = _FakeAdmin();
    credentials = _FakeCreds();
    manifest = MemoryManifest(_liveManifest());
    reader = FakeStructuredReader();
    moveReader = GitHubMoveReader(
      api: gitData,
      credentials: credentials,
      manifest: manifest,
    );
    source = GitHubMoveSource(
      reader: moveReader,
      gitData: gitData,
      repoAdmin: admin,
      credentials: credentials,
      manifest: manifest,
      verifier: MovedSiteVerifier(
        reader: reader,
        markerCodec: const CloudflarePublishMarkerCodec(),
        validateMovedHtml: (_) async => true,
        sleep: (_) async {},
        attempts: 1,
      ),
      clock: () => 1700000000000,
    );
  });

  test('readAnchor proves the exact live source and owned paths', () async {
    final anchor = await source.readAnchor(moveGitHubTarget);

    final value = anchor.getOrElse((f) => fail('expected success, got $f'));
    expect(value.value, moveGitHubHead);
    expect(value.branch!.value, 'main');
    expect(value.ownedPaths, ['books.json', 'index.html', 'library.json']);
  });

  test(
    'readAnchor refuses a tree that no longer matches the local head',
    () async {
      gitData.tree = _tree(head: 'f' * 40);

      final anchor = await source.readAnchor(moveGitHubTarget);

      expect(anchor.isLeft(), isTrue);
      anchor.mapLeft((failure) {
        expect(failure, isA<ValidationFailure>());
      });
    },
  );

  test('readAnchor refuses credential drift to another repository', () async {
    credentials.targetRepoValue = 'me/another';

    final anchor = await source.readAnchor(moveGitHubTarget);

    expect(anchor.isLeft(), isTrue);
    expect(credentials.reads, 1);
    expect(gitData.headTreeCalls, 0);
  });

  test('retire writes moved pages plus exact deletions in one expected-head '
      'commit, verifies, then saves the retired manifest', () async {
    final pending = _pending();
    reader
      ..body('', pending.retirement.indexHtml)
      ..absent('books.json');
    gitData.commitResult = const PublishCommitSuccess('retired-head', []);

    final result = await source.retire(pending);

    expect(result.isRight(), isTrue);
    expect(gitData.commits, hasLength(1));
    final commit = gitData.commits.single;
    expect(commit.expectedHead, moveGitHubHead);
    expect(commit.branch, 'main');
    expect(commit.files.map((file) => file.path), ['index.html', '404.html']);
    expect(commit.deletes, ['books.json', 'library.json']);
    expect(commit.token, _token);

    final saved = manifest.value;
    expect(saved.state, PublishState.retired);
    expect(saved.headSha, 'retired-head');
    expect(saved.fileShas.keys, ['index.html', '404.html']);
    expect(saved.ownershipConfirmed, isTrue);
  });

  test('retire reuses already-retired bytes without a second commit', () async {
    final pending = _pending();
    reader
      ..body('', pending.retirement.indexHtml)
      ..absent('books.json');
    final moved = {
      for (final file in MovePlanForTest.files(pending)) file.path: file.gitSha,
    };
    gitData.tree = GitHubTreeSnapshot(
      repo: 'me/library',
      branch: 'main',
      headSha: 'already-retired-head',
      files: moved,
      truncated: false,
    );

    final result = await source.retire(pending);

    expect(result.isRight(), isTrue);
    expect(gitData.commits, isEmpty);
    expect(manifest.value.state, PublishState.retired);
    expect(manifest.value.headSha, 'already-retired-head');
  });

  test('a stale expected head aborts retirement and saves nothing', () async {
    final pending = _pending();
    gitData.commitResult = const PublishCommitStale();

    final result = await source.retire(pending);

    final failure = result.swap().toNullable()!;
    expect(failure, isA<ValidationFailure>());
    expect(manifest.saves, 0);
  });

  test('failed retirement read-back saves nothing', () async {
    final pending = _pending();
    reader
      ..body('', utf8.encode('<html>stale</html>'))
      ..absent('books.json');

    final result = await source.retire(pending);

    final failure = result.swap().toNullable()!;
    expect(failure, isA<ValidationFailure>());
    expect(manifest.saves, 0);
  });

  test(
    'a source whose local record no longer matches is never retired',
    () async {
      final pending = _pending();
      manifest.value = _liveManifest(head: 'd' * 40);

      final result = await source.retire(pending);

      final failure = result.swap().toNullable()!;
      expect(failure, isA<ValidationFailure>());
      expect(gitData.commits, isEmpty);
      expect(manifest.saves, 0);
    },
  );

  test('Skip is allowed only when the exact repository is gone', () async {
    final pending = _pending();

    admin.details = null;
    expect((await source.authorizeSkip(pending)).isRight(), isTrue);

    admin.details = const GitHubRepoDetails(
      fullName: 'me/library',
      ownerLogin: 'me',
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      canPush: true,
      canAdmin: true,
    );
    final refused = await source.authorizeSkip(pending);
    expect(refused.isLeft(), isTrue);
    refused.mapLeft((failure) {
      expect(
        (failure as ValidationFailure).message,
        MoveSiteMessages.skipNotAllowed,
      );
    });
  });

  test(
    'Skip refuses credential drift instead of hiding another site',
    () async {
      final pending = _pending();
      credentials.targetRepoValue = 'me/another';

      final result = await source.authorizeSkip(pending);

      final failure = result.swap().toNullable()!;
      expect(failure, isA<ValidationFailure>());
      expect(admin.repositoryCalls, 0);
    },
  );
}

PendingMove _pending() => movePending(
  oldTarget: moveGitHubTarget,
  newTarget: moveCloudflareTarget,
  indexHtml: utf8.encode('<html>moved</html>'),
);

PublishManifest _liveManifest({String? head}) => PublishManifest(
  repo: 'me/library',
  branch: 'main',
  headSha: head ?? moveGitHubHead,
  ownershipConfirmed: true,
  state: PublishState.live,
  fileShas: _shas(const ['books.json', 'index.html', 'library.json']),
);

GitHubTreeSnapshot _tree({String? head}) => GitHubTreeSnapshot(
  repo: 'me/library',
  branch: 'main',
  headSha: head ?? moveGitHubHead,
  files: _shas(const ['books.json', 'index.html', 'library.json']),
  truncated: false,
);

final class _FakeGitData implements GitHubGitDataApi {
  GitHubTreeSnapshot tree = _tree();
  PublishCommitResult commitResult = const PublishCommitSuccess(
    'retired-head',
    [],
  );
  int headTreeCalls = 0;
  final List<
    ({
      List<DesiredFile> files,
      List<String> deletes,
      String expectedHead,
      String branch,
      String token,
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
  }) async {
    headTreeCalls++;
    return tree;
  }

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
      token: token,
    ));
    return commitResult;
  }
}

final class _FakeAdmin implements GitHubRepoAdminApi {
  GitHubRepoDetails? details;
  int repositoryCalls = 0;

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) async {
    repositoryCalls++;
    return details;
  }

  @override
  Future<String> currentUserLogin(String token) async => 'me';

  @override
  Future<RepoListing> userRepos(String token) async =>
      const RepoListing(repos: [], truncated: false);

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async => _pages;

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) async => const RepoCreated('main');

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {}
}

final class _FakeCreds implements PublishCredentialStore {
  String? tokenValue = _token;
  String? targetRepoValue = 'me/library';
  int reads = 0;

  @override
  Future<String?> token() async => tokenValue;

  @override
  Future<String?> targetRepo() async {
    reads++;
    return targetRepoValue;
  }

  @override
  Future<void> setToken(String value) async => tokenValue = value;

  @override
  Future<void> clearToken() async => tokenValue = null;

  @override
  Future<void> setTargetRepo(String value) async => targetRepoValue = value;

  @override
  Future<void> clearTargetRepo() async => targetRepoValue = null;
}

/// Exposes the exact moved-file shas the plan will write.
abstract final class MovePlanForTest {
  static List<({String path, String gitSha})> files(PendingMove pending) {
    final plan = MovePlan.forGitHub(pending)!;
    return [
      for (final file in plan.files) (path: file.path, gitSha: file.gitSha),
    ];
  }
}
