/// Counts every GitHub commit this app makes, for the availability lane's
/// hourly budget (infrastructure; ADR 0019 Decision 8, plan AV6).
///
/// Why a decorator (beginner note): GitHub Pages rebuilds the site after
/// every commit and allows only about 10 builds an hour. The lane must count
/// EVERY commit from this app — catalogue, events, moves, retirements and its
/// own — not just its own. Every one of them goes through
/// [GitHubGitDataApi.commitFiles], so wrapping that one method records them
/// all, and no publish flow can forget to report its commit. A decorator is a
/// class that implements the same interface as the object it wraps and
/// forwards every call to it, adding one small behaviour on the way.
///
/// Only an ACCEPTED commit counts ([PublishCommitSuccess]): a stale head or
/// an HTTP error wrote nothing, so GitHub builds nothing. The recorder must
/// never fail the commit: recording is best-effort, because the budget is a
/// courtesy limit and the commit already happened.
library;

import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';

/// Forwards every call to [GitHubApi] and reports each accepted commit.
final class CommitRecordingGitHubApi implements GitHubApi {
  /// Wraps [inner]; [onCommitted] receives the acceptance time from [clock]
  /// (epoch milliseconds).
  const CommitRecordingGitHubApi({
    required GitHubApi inner,
    required void Function(int acceptedAt) onCommitted,
    required int Function() clock,
  }) : _inner = inner,
       _onCommitted = onCommitted,
       _clock = clock;

  final GitHubApi _inner;
  final void Function(int acceptedAt) _onCommitted;
  final int Function() _clock;

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
    final result = await _inner.commitFiles(
      owner: owner,
      repo: repo,
      branch: branch,
      token: token,
      plan: plan,
      commitMessage: commitMessage,
      expectedHead: expectedHead,
      deletePaths: deletePaths,
      onBlobStored: onBlobStored,
    );
    if (result is PublishCommitSuccess) _onCommitted(_clock());
    return result;
  }

  // --- plain forwarding: nothing below changes behaviour -----------------

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) => _inner.requestDeviceCode(clientId: clientId, scope: scope);

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) => _inner.pollAccessToken(clientId: clientId, deviceCode: deviceCode);

  @override
  Future<String> currentUserLogin(String token) =>
      _inner.currentUserLogin(token);

  @override
  Future<RepoListing> userRepos(String token) => _inner.userRepos(token);

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) => _inner.repository(owner: owner, repo: repo, token: token);

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) => _inner.pagesSite(owner: owner, repo: repo, token: token);

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) => _inner.createUserRepo(name: name, token: token);

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => _inner.enablePages(
    owner: owner,
    repo: repo,
    branch: branch,
    token: token,
  );

  @override
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) =>
      _inner.branchHead(owner: owner, repo: repo, branch: branch, token: token);

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) => _inner.treeAt(
    owner: owner,
    repo: repo,
    branch: branch,
    headSha: headSha,
    token: token,
  );
}
