import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/setup_github_repo.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';

/// Scriptable API covering only the setup path; everything else throws.
class _SetupApi implements GitHubApi {
  _SetupApi({
    this.createResult = const RepoCreated('main'),
    this.lookupBranch = 'main',
    this.throwOnUser = false,
    this.throwOnPages = false,
  });

  static const String login = 'booklover';
  final RepoCreateResult createResult;
  final String? lookupBranch;
  final bool throwOnUser;
  final bool throwOnPages;

  String? createdName;
  String? pagesBranch;

  @override
  Future<String> currentUserLogin(String token) async {
    if (throwOnUser) throw const GitHubApiException('bad credentials');
    return login;
  }

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) async {
    createdName = name;
    return createResult;
  }

  @override
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  }) async => lookupBranch;

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    if (throwOnPages) throw const GitHubApiException('pages boom');
    pagesBranch = branch;
  }

  // Unused in these tests.
  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) => throw UnimplementedError();
  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) => throw UnimplementedError();
  @override
  Future<List<GitHubRepo>> userRepos(String token) =>
      throw UnimplementedError();
  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => throw UnimplementedError();
  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
  }) => throw UnimplementedError();
}

class _MemCreds implements PublishCredentialStore {
  String? storedTarget;
  @override
  Future<String?> token() async => 'tok';
  @override
  Future<String?> targetRepo() async => storedTarget;
  @override
  Future<void> setTargetRepo(String target) async => storedTarget = target;
  @override
  Future<void> setToken(String token) async {}
  @override
  Future<void> clearToken() async {}
}

void main() {
  // Scenarios mirror Localcart Orange's github_setup.rs tests.
  test('fresh account: creates repo, enables Pages, stores target', () async {
    final api = _SetupApi();
    final creds = _MemCreds();
    final result = await SetupGitHubRepo(
      api,
      creds,
    ).call(token: 'tok', repoName: 'my-library');

    final r = result.getOrElse((f) => fail('expected success, got $f'));
    expect(r.owner, 'booklover');
    expect(r.repo, 'my-library');
    expect(r.branch, 'main');
    expect(r.created, isTrue);
    expect(api.createdName, 'my-library');
    expect(api.pagesBranch, 'main');
    expect(creds.storedTarget, 'booklover/my-library');
  });

  test('existing repo (422) is adopted with its real branch', () async {
    final api = _SetupApi(
      createResult: const RepoAlreadyExists(),
      lookupBranch: 'master',
    );
    final creds = _MemCreds();
    final result = await SetupGitHubRepo(
      api,
      creds,
    ).call(token: 'tok', repoName: 'my-library');

    final r = result.getOrElse((f) => fail('expected success, got $f'));
    expect(r.created, isFalse);
    expect(r.branch, 'master');
    expect(api.pagesBranch, 'master');
    expect(creds.storedTarget, 'booklover/my-library');
  });

  test('adopted repo with unknown branch falls back to main', () async {
    final api = _SetupApi(
      createResult: const RepoAlreadyExists(),
      lookupBranch: null,
    );
    final result = await SetupGitHubRepo(
      api,
      _MemCreds(),
    ).call(token: 'tok', repoName: 'r');
    final r = result.getOrElse((f) => fail('expected success, got $f'));
    expect(r.branch, 'main');
  });

  test('bad token fails closed with NetworkFailure, stores nothing', () async {
    final creds = _MemCreds();
    final result = await SetupGitHubRepo(
      _SetupApi(throwOnUser: true),
      creds,
    ).call(token: 'bad', repoName: 'r');
    expect(result.isLeft(), isTrue);
    result.mapLeft((f) => expect(f, isA<NetworkFailure>()));
    expect(creds.storedTarget, isNull);
  });

  test('Pages failure fails closed, stores nothing', () async {
    final creds = _MemCreds();
    final result = await SetupGitHubRepo(
      _SetupApi(throwOnPages: true),
      creds,
    ).call(token: 'tok', repoName: 'r');
    expect(result.isLeft(), isTrue);
    expect(creds.storedTarget, isNull);
  });

  group('hostile repo names are rejected before any network call', () {
    for (final bad in [
      '',
      ' ',
      'has space',
      'a/b',
      '../../etc',
      '.',
      '..',
      'emoji📚',
      'x' * 101,
      'a?b',
      'a#b',
    ]) {
      test('"$bad" → ValidationFailure', () async {
        final api = _SetupApi();
        final result = await SetupGitHubRepo(
          api,
          _MemCreds(),
        ).call(token: 'tok', repoName: bad);
        expect(result.isLeft(), isTrue);
        result.mapLeft((f) => expect(f, isA<ValidationFailure>()));
        expect(api.createdName, isNull); // never reached the network
      });
    }

    test('leading/trailing whitespace is trimmed, then accepted', () async {
      final api = _SetupApi();
      final result = await SetupGitHubRepo(
        api,
        _MemCreds(),
      ).call(token: 'tok', repoName: '  my-library  ');
      expect(result.isRight(), isTrue);
      expect(api.createdName, 'my-library');
    });
  });
}
