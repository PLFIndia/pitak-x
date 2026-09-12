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
    this.details = const GitHubRepoDetails(
      fullName: 'booklover/my-library',
      ownerLogin: login,
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      canPush: true,
      canAdmin: true,
    ),
    this.pages,
    this.throwOnUser = false,
    this.throwOnPages = false,
    this.throwOnRepository = false,
  });

  static const String login = 'booklover';
  final RepoCreateResult createResult;

  /// What `repository()` answers (null = 404).
  final GitHubRepoDetails? details;

  /// What `pagesSite()` answers (null = Pages off).
  final PagesSite? pages;
  final bool throwOnUser;
  final bool throwOnPages;
  final bool throwOnRepository;

  String? createdName;
  String? pagesBranch;
  int repositoryCalls = 0;
  int pagesSiteCalls = 0;

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
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) async {
    repositoryCalls++;
    if (throwOnRepository) throw const GitHubApiException('boom');
    return details;
  }

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    pagesSiteCalls++;
    return pages;
  }

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
  Future<RepoListing> userRepos(String token) => throw UnimplementedError();
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
    List<String> deletePaths = const [],
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
  Future<void> clearTargetRepo() async => storedTarget = null;
  @override
  Future<void> setToken(String token) async {}
  @override
  Future<void> clearToken() async {}
}

GitHubRepoDetails _details({
  String ownerLogin = _SetupApi.login,
  String defaultBranch = 'main',
  bool isPrivate = false,
  bool isArchived = false,
  bool canPush = true,
  bool canAdmin = true,
}) => GitHubRepoDetails(
  fullName: '$ownerLogin/my-library',
  ownerLogin: ownerLogin,
  isPrivate: isPrivate,
  isArchived: isArchived,
  defaultBranch: defaultBranch,
  canPush: canPush,
  canAdmin: canAdmin,
);

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

  test('existing repo (422) is adopted: Pages off → enabled on its real '
      'default branch', () async {
    final api = _SetupApi(
      createResult: const RepoAlreadyExists(),
      details: _details(defaultBranch: 'master'),
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

  group('N09 — adopting an existing repository (the advanced picker)', () {
    Future<
      ({_SetupApi api, _MemCreds creds, GitHubSetupResult? ok, Failure? fail})
    >
    adopt(_SetupApi api, {String fullName = 'booklover/my-library'}) async {
      final creds = _MemCreds();
      final result = await SetupGitHubRepo(
        api,
        creds,
      ).adopt(token: 'tok', fullName: fullName);
      return (
        api: api,
        creds: creds,
        ok: result.toNullable(),
        fail: result.fold((f) => f, (_) => null),
      );
    }

    test(
      'Pages already on (branch, root) → adopted, nothing enabled',
      () async {
        final r = await adopt(
          _SetupApi(
            details: _details(),
            pages: const PagesSite(
              sourceBranch: 'gh-pages',
              sourcePath: '/',
              isWorkflowBuild: false,
            ),
          ),
        );
        expect(r.fail, isNull);
        expect(r.ok!.created, isFalse);
        // The branch the SITE is served from, not the default branch.
        expect(r.ok!.branch, 'gh-pages');
        expect(r.api.pagesBranch, isNull); // enablePages not called
        expect(r.creds.storedTarget, 'booklover/my-library');
      },
    );

    test('Pages off → enabled on the default branch, then stored', () async {
      final r = await adopt(_SetupApi(details: _details(defaultBranch: 'dev')));
      expect(r.fail, isNull);
      expect(r.api.pagesBranch, 'dev');
      expect(r.ok!.branch, 'dev');
      expect(r.creds.storedTarget, 'booklover/my-library');
    });

    test("another account's repo is refused (D1-a), nothing stored", () async {
      final r = await adopt(
        _SetupApi(details: _details(ownerLogin: 'someone-else')),
        fullName: 'someone-else/my-library',
      );
      expect(r.fail, isA<ValidationFailure>());
      expect(r.api.pagesSiteCalls, 0); // refused before touching Pages
      expect(r.creds.storedTarget, isNull);
    });

    test('a target whose owner segment differs from the signed-in login is '
        'refused even before the repository lookup', () async {
      final r = await adopt(_SetupApi(), fullName: 'other/my-library');
      expect(r.fail, isA<ValidationFailure>());
      expect(r.api.repositoryCalls, 0);
      expect(r.creds.storedTarget, isNull);
    });

    test('repo not found (404) → refused, nothing stored', () async {
      final r = await adopt(_SetupApi(details: null));
      expect(r.fail, isA<ValidationFailure>());
      expect(r.creds.storedTarget, isNull);
    });

    test('archived repo → refused', () async {
      final r = await adopt(_SetupApi(details: _details(isArchived: true)));
      expect(r.fail, isA<ValidationFailure>());
      expect(r.creds.storedTarget, isNull);
    });

    test('no push permission → refused', () async {
      final r = await adopt(_SetupApi(details: _details(canPush: false)));
      expect(r.fail, isA<ValidationFailure>());
      expect(r.creds.storedTarget, isNull);
    });

    test('private repo → refused with a plan explanation', () async {
      final r = await adopt(_SetupApi(details: _details(isPrivate: true)));
      expect(r.fail, isA<ValidationFailure>());
      expect((r.fail! as ValidationFailure).message, contains('private'));
      expect(r.creds.storedTarget, isNull);
    });

    test('Pages served from /docs → refused (D2-a)', () async {
      final r = await adopt(
        _SetupApi(
          details: _details(),
          pages: const PagesSite(
            sourceBranch: 'main',
            sourcePath: '/docs',
            isWorkflowBuild: false,
          ),
        ),
      );
      expect(r.fail, isA<ValidationFailure>());
      expect(r.api.pagesBranch, isNull); // never re-pointed silently
      expect(r.creds.storedTarget, isNull);
    });

    test('Pages built by a workflow → refused (D2-a)', () async {
      final r = await adopt(
        _SetupApi(
          details: _details(),
          pages: const PagesSite(
            sourceBranch: null,
            sourcePath: null,
            isWorkflowBuild: true,
          ),
        ),
      );
      expect(r.fail, isA<ValidationFailure>());
      expect(r.creds.storedTarget, isNull);
    });

    test('Pages off + no admin right → refused (cannot enable)', () async {
      final r = await adopt(_SetupApi(details: _details(canAdmin: false)));
      expect(r.fail, isA<ValidationFailure>());
      expect(r.api.pagesBranch, isNull);
      expect(r.creds.storedTarget, isNull);
    });

    test('transport failure → NetworkFailure, nothing stored', () async {
      final r = await adopt(_SetupApi(throwOnRepository: true));
      expect(r.fail, isA<NetworkFailure>());
      expect(r.creds.storedTarget, isNull);
    });

    test(
      'a malformed target string is refused before any network call',
      () async {
        for (final bad in ['no-slash', 'a/b/c', '/repo', 'owner/', 'o/r?x']) {
          final r = await adopt(_SetupApi(), fullName: bad);
          expect(r.fail, isA<ValidationFailure>(), reason: bad);
          expect(r.api.repositoryCalls, 0, reason: bad);
        }
      },
    );

    test('refusal messages never echo the repository name', () async {
      // The name is the user's own, but keeping copy fixed means a hostile
      // API response can never steer what the dialog says.
      final r = await adopt(
        _SetupApi(details: _details(ownerLogin: 'someone-else')),
        fullName: 'someone-else/my-library',
      );
      expect(
        (r.fail! as ValidationFailure).message,
        isNot(contains('someone-else')),
      );
    });
  });

  group('N09 — the 422 adopt path applies the same Pages rules', () {
    test('existing repo already serving from /docs → refused', () async {
      final api = _SetupApi(
        createResult: const RepoAlreadyExists(),
        details: _details(),
        pages: const PagesSite(
          sourceBranch: 'main',
          sourcePath: '/docs',
          isWorkflowBuild: false,
        ),
      );
      final creds = _MemCreds();
      final result = await SetupGitHubRepo(
        api,
        creds,
      ).call(token: 'tok', repoName: 'my-library');
      expect(result.isLeft(), isTrue);
      result.mapLeft((f) => expect(f, isA<ValidationFailure>()));
      expect(creds.storedTarget, isNull);
    });

    test('existing repo already on Pages (gh-pages) → that branch', () async {
      final api = _SetupApi(
        createResult: const RepoAlreadyExists(),
        details: _details(),
        pages: const PagesSite(
          sourceBranch: 'gh-pages',
          sourcePath: '/',
          isWorkflowBuild: false,
        ),
      );
      final result = await SetupGitHubRepo(
        api,
        _MemCreds(),
      ).call(token: 'tok', repoName: 'my-library');
      final r = result.getOrElse((f) => fail('expected success, got $f'));
      expect(r.branch, 'gh-pages');
      expect(api.pagesBranch, isNull);
    });

    test(
      'existing repo that vanished between create and lookup → refused',
      () async {
        final api = _SetupApi(
          createResult: const RepoAlreadyExists(),
          details: null,
        );
        final creds = _MemCreds();
        final result = await SetupGitHubRepo(
          api,
          creds,
        ).call(token: 'tok', repoName: 'my-library');
        expect(result.isLeft(), isTrue);
        expect(creds.storedTarget, isNull);
      },
    );
  });
}
