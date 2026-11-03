import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/infrastructure/commit_recording_github_api.dart';

/// Every accepted GitHub commit is counted for the lane's hourly budget
/// (ADR 0019 Decision 8, plan AV6); nothing else changes.
void main() {
  late _ScriptedApi inner;
  late List<int> recorded;
  late CommitRecordingGitHubApi api;

  setUp(() {
    inner = _ScriptedApi();
    recorded = [];
    api = CommitRecordingGitHubApi(
      inner: inner,
      onCommitted: recorded.add,
      clock: () => 4242,
    );
  });

  Future<PublishCommitResult> commit() => api.commitFiles(
    owner: 'me',
    repo: 'lib',
    branch: 'main',
    token: 't',
    plan: GitHubCommitPlan(files: const [], knownBlobShas: const {}),
    commitMessage: 'm',
    expectedHead: 'HEAD',
    deletePaths: const ['availability.json'],
  );

  test('an accepted commit is recorded once, with the clock time', () async {
    inner.result = const PublishCommitSuccess('c1', []);
    final result = await commit();
    expect(result, isA<PublishCommitSuccess>());
    expect(recorded, [4242]);
    expect(inner.lastDeletePaths, ['availability.json']);
  });

  test(
    'a stale head or an HTTP error wrote nothing and is not counted',
    () async {
      inner.result = const PublishCommitStale();
      await commit();
      inner.result = const PublishCommitHttpError(500, '');
      await commit();
      expect(recorded, isEmpty);
    },
  );

  test('a thrown commit is not counted and still throws', () async {
    inner.throwOnCommit = true;
    await expectLater(commit(), throwsA(isA<GitHubApiException>()));
    expect(recorded, isEmpty);
  });

  test('every other call is forwarded unchanged', () async {
    await api.requestDeviceCode(clientId: 'c', scope: 's');
    await api.pollAccessToken(clientId: 'c', deviceCode: 'd');
    await api.currentUserLogin('t');
    await api.userRepos('t');
    await api.repository(owner: 'me', repo: 'lib', token: 't');
    await api.pagesSite(owner: 'me', repo: 'lib', token: 't');
    await api.createUserRepo(name: 'lib', token: 't');
    await api.enablePages(owner: 'me', repo: 'lib', branch: 'main', token: 't');
    await api.branchHead(owner: 'me', repo: 'lib', branch: 'main', token: 't');
    await api.treeAt(
      owner: 'me',
      repo: 'lib',
      branch: 'main',
      headSha: 'HEAD',
      token: 't',
    );
    expect(inner.calls, [
      'requestDeviceCode',
      'pollAccessToken',
      'currentUserLogin',
      'userRepos',
      'repository',
      'pagesSite',
      'createUserRepo',
      'enablePages',
      'branchHead',
      'treeAt',
    ]);
    expect(recorded, isEmpty);
  });
}

final class _ScriptedApi implements GitHubApi {
  PublishCommitResult result = const PublishCommitSuccess('c', []);
  bool throwOnCommit = false;
  List<String>? lastDeletePaths;
  final List<String> calls = [];

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
    lastDeletePaths = deletePaths;
    if (throwOnCommit) throw const GitHubApiException('synthetic');
    return result;
  }

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async {
    calls.add('requestDeviceCode');
    return const DeviceCodeGrant(
      deviceCode: 'd',
      userCode: 'u',
      verificationUri: 'https://github.com/login/device',
      expiresInSeconds: 900,
      intervalSeconds: 5,
    );
  }

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    calls.add('pollAccessToken');
    return const PollPending();
  }

  @override
  Future<String> currentUserLogin(String token) async {
    calls.add('currentUserLogin');
    return 'me';
  }

  @override
  Future<RepoListing> userRepos(String token) async {
    calls.add('userRepos');
    return const RepoListing(repos: [], truncated: false);
  }

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) async {
    calls.add('repository');
    return null;
  }

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    calls.add('pagesSite');
    return null;
  }

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) async {
    calls.add('createUserRepo');
    return const RepoAlreadyExists();
  }

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async => calls.add('enablePages');

  @override
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    calls.add('branchHead');
    return 'HEAD';
  }

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) async {
    calls.add('treeAt');
    return GitHubTreeSnapshot(
      repo: '$owner/$repo',
      branch: branch,
      headSha: headSha,
      files: const {},
      truncated: false,
    );
  }
}
