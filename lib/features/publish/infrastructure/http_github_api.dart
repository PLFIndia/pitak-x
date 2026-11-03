/// HTTP implementation of [GitHubApi] (infrastructure, AGENTS.md §3.3, #32).
///
/// Ports the Kotlin GitHub stack (`GitHubAuthApi`, `GitHubContentsApi`,
/// `GitHubGitDataApi`, `GitTreePublisher`) into one cohesive client over
/// `http`. The Git Data flow is the atomic-incremental commit, written by
/// `GitHubCommitWriter` (`http_github_commit.dart`):
///   ref → blobs(only those GitHub does not hold, paced) → tree(base_tree +
///   changed) → commit → move ref.
/// The branch ref moves exactly once at the end, so a failed publish leaves the
/// live page on its previous commit. Reading the state a commit plans against
/// is `GitHubTreeReader` (`http_github_tree.dart`).
///
/// Auth host is github.com (device flow); API host is api.github.com. Tokens
/// are passed per-call as a Bearer header — an unauthenticated API call can't
/// be made by accident.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/infrastructure/github_http_support.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_commit.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_tree.dart';

/// `http`-backed GitHub client.
final class HttpGitHubApi implements GitHubApi {
  /// Creates the client. [authBase]/[apiBase] are overridable for tests.
  ///
  /// [sleep] and [clock] (epoch ms) pace a commit's blob uploads (plan J8);
  /// tests pass fakes so a multi-file commit does not wait in real time.
  HttpGitHubApi({
    required http.Client client,
    Uri? authBase,
    Uri? apiBase,
    Future<void> Function(Duration)? sleep,
    int Function()? clock,
  }) : _client = client,
       _authBase = authBase ?? Uri.parse('https://github.com'),
       _apiBase = apiBase ?? Uri.parse('https://api.github.com'),
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final http.Client _client;
  final Uri _authBase;
  final Uri _apiBase;
  final Future<void> Function(Duration) _sleep;
  final int Function() _clock;

  static const String _accept = 'application/vnd.github+json';

  /// Git branch names the app will put into a URL path. Git allows far more,
  /// but every branch the app creates or serves Pages from is plain
  /// (`main`, `gh-pages`, `release/1.2`); anything else is refused rather
  /// than URL-encoded, because a `..` or `?` here would change which
  /// endpoint later Git Data calls hit. The journal uses this same grammar.

  /// Page budget for [userRepos] (N09, D4-a): 10 × 100 = at most 1000
  /// repositories, ~10 sequential requests. Bounds both network time and
  /// memory on a phone; the listing is flagged `truncated` past this.
  static const int maxRepoPages = 10;

  /// Parses `rel="next"` out of a `Link` header into the page NUMBER only.
  /// The URL inside the header is server-controlled text and is never
  /// fetched as-is; the next request is rebuilt against our own API base.
  /// (Adapted from `github` 9.17.0 `PaginationHelper`, MIT, DirectCode —
  /// which follows the link URL verbatim; here only the number survives.)
  static final RegExp _nextPage = RegExp(
    r'<[^>]*[?&]page=(\d+)[^>]*>\s*;\s*rel="next"',
  );

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': _accept,
  };

  // --- Device flow ---------------------------------------------------------

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async {
    final resp = await _post(
      _authBase.replace(path: '/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {'client_id': clientId, 'scope': scope},
    );
    final json = decodeGitHubObject(resp.body);
    final deviceCode = json['device_code'] as String?;
    final userCode = json['user_code'] as String?;
    final uri = json['verification_uri'] as String?;
    if (deviceCode == null || userCode == null || uri == null) {
      throw const GitHubApiException('Malformed device-code response');
    }
    return DeviceCodeGrant(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: uri,
      expiresInSeconds: (json['expires_in'] as int?) ?? 900,
      intervalSeconds: (json['interval'] as int?) ?? 5,
    );
  }

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    final resp = await _post(
      _authBase.replace(path: '/login/oauth/access_token'),
      headers: {'Accept': 'application/json'},
      body: {
        'client_id': clientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );
    final json = decodeGitHubObject(resp.body);
    final token = json['access_token'] as String?;
    if (token != null && token.isNotEmpty) {
      return PollAuthorized(token, (json['scope'] as String?) ?? '');
    }
    switch (json['error'] as String?) {
      case 'authorization_pending':
        return const PollPending();
      case 'slow_down':
        return const PollPending(slowDown: true);
      case 'access_denied':
        return const PollDenied();
      case 'expired_token':
        return const PollExpired();
      case null:
        return const PollPending();
      default:
        // Protocol-fatal (`device_flow_disabled`, `incorrect_device_code`,
        // `unsupported_grant_type`, …): the grant itself is dead. Returned
        // as a RESULT, not thrown — exceptions from this method mean
        // "transport hiccup, retry", and retrying a dead grant can never
        // succeed (RFC 8628 §3.5).
        return PollFatal(
          (json['error_description'] as String?) ?? '${json['error']}',
        );
    }
  }

  // --- Account / repos -----------------------------------------------------

  @override
  Future<String> currentUserLogin(String token) async {
    final resp = await _get(
      _apiBase.replace(path: '/user'),
      headers: _authHeaders(token),
    );
    final login = decodeGitHubObject(resp.body)['login'] as String?;
    if (login == null) throw const GitHubApiException('No login in /user');
    return login;
  }

  @override
  Future<RepoListing> userRepos(String token) async {
    final repos = <GitHubRepo>[];
    var page = 1;
    while (true) {
      final resp = await _get(
        _apiBase.replace(
          path: '/user/repos',
          queryParameters: {
            // D1-a: only repositories this account OWNS. The Pages URL is
            // then always `<login>.github.io/...`, and org/collaborator
            // repositories never reach the device at all.
            'affiliation': 'owner',
            'per_page': '100',
            'sort': 'updated',
            'page': '$page',
          },
        ),
        headers: _authHeaders(token),
      );
      if (resp.statusCode >= 400) {
        throw GitHubApiException(
          'repo list: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode,
        );
      }
      final list = jsonDecode(resp.body);
      if (list is! List) throw const GitHubApiException('Malformed repo list');
      repos.addAll([
        for (final e in list.whereType<Map<String, dynamic>>())
          if (e['full_name'] is String)
            GitHubRepo(
              fullName: e['full_name'] as String,
              isPrivate: (e['private'] as bool?) ?? false,
              htmlUrl: e['html_url'] as String?,
            ),
      ]);
      final next = _nextPageOf(resp.headers['link']);
      if (next == null) return RepoListing(repos: repos, truncated: false);
      if (page >= maxRepoPages) {
        return RepoListing(repos: repos, truncated: true);
      }
      page = next;
    }
  }

  /// The page number in a `Link` header's `rel="next"` entry, or null when
  /// there is no next page.
  int? _nextPageOf(String? linkHeader) {
    if (linkHeader == null) return null;
    final m = _nextPage.firstMatch(linkHeader);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final resp = await _get(
      _apiBase.replace(path: '/repos/$owner/$repo'),
      headers: _authHeaders(token),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 400) {
      throw GitHubApiException(
        'repository: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final json = decodeGitHubObject(resp.body);
    final fullName = json['full_name'];
    final ownerLogin = (json['owner'] as Map?)?['login'];
    final isPrivate = json['private'];
    final isArchived = json['archived'];
    final defaultBranch = json['default_branch'];
    if (fullName is! String ||
        ownerLogin is! String ||
        isPrivate is! bool ||
        isArchived is! bool ||
        defaultBranch is! String) {
      throw const GitHubApiException('Malformed repository response');
    }
    _requireBranchName(defaultBranch);
    // `permissions` is only present for authenticated calls. Missing means
    // we cannot prove push rights → treat as none (fail closed).
    final permissions = json['permissions'];
    final canPush = permissions is Map && permissions['push'] == true;
    final canAdmin = permissions is Map && permissions['admin'] == true;
    return GitHubRepoDetails(
      fullName: fullName,
      ownerLogin: ownerLogin,
      isPrivate: isPrivate,
      isArchived: isArchived,
      defaultBranch: defaultBranch,
      canPush: canPush,
      canAdmin: canAdmin,
    );
  }

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final resp = await _get(
      _apiBase.replace(path: '/repos/$owner/$repo/pages'),
      headers: _authHeaders(token),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 400) {
      throw GitHubApiException(
        'pages: HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final json = decodeGitHubObject(resp.body);
    // `build_type` is absent on older API shapes; GitHub's default for a
    // branch-sourced site is `legacy`.
    final buildType = json['build_type'] ?? 'legacy';
    if (buildType == 'workflow') {
      return const PagesSite(
        sourceBranch: null,
        sourcePath: null,
        isWorkflowBuild: true,
      );
    }
    if (buildType != 'legacy') {
      throw const GitHubApiException('Malformed Pages response');
    }
    final source = json['source'];
    final branch = source is Map ? source['branch'] : null;
    final path = source is Map ? source['path'] : null;
    if (branch is! String || path is! String) {
      throw const GitHubApiException('Malformed Pages response');
    }
    _requireBranchName(branch);
    return PagesSite(
      sourceBranch: branch,
      sourcePath: path,
      isWorkflowBuild: false,
    );
  }

  /// Refuses a branch name the app must not put into a URL path.
  void _requireBranchName(String branch) {
    if (!GitHubBranchName.isValid(branch)) {
      throw const GitHubApiException('Unsafe branch name');
    }
  }

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) async {
    // Mirrors Localcart Orange's github_setup.rs: auto_init so the branch
    // exists for the first commit; 422 = "name already exists" → the caller
    // adopts the repo (idempotent reconnect / reinstall, §12).
    final resp = await _post(
      _apiBase.replace(path: '/user/repos'),
      headers: _authHeaders(token),
      jsonBody: {
        'name': name,
        'private': false,
        'auto_init': true,
        'description': 'Library catalogue published by Pitak',
      },
    );
    if (resp.statusCode == 422) return const RepoAlreadyExists();
    if (resp.statusCode >= 400) {
      throw GitHubApiException(
        'repo create: HTTP ${resp.statusCode} ${gitHubExcerpt(resp.body)}',
        statusCode: resp.statusCode,
      );
    }
    final branch =
        decodeGitHubObject(resp.body)['default_branch'] as String? ?? 'main';
    return RepoCreated(branch);
  }

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    _requireBranchName(branch);
    final resp = await _post(
      _apiBase.replace(path: '/repos/$owner/$repo/pages'),
      headers: _authHeaders(token),
      jsonBody: {
        'source': {'branch': branch},
      },
    );
    // 409 = Pages already enabled — converged, not an error (§12).
    if (resp.statusCode >= 400 && resp.statusCode != 409) {
      throw GitHubApiException(
        'enable Pages: HTTP ${resp.statusCode} ${gitHubExcerpt(resp.body)}',
        statusCode: resp.statusCode,
      );
    }
  }

  // --- Git Data: read head + tree (manifest reconciliation) ----------------

  @override
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => GitHubTreeReader(
    client: _client,
    apiBase: _apiBase,
  ).readHead(owner: owner, repo: repo, branch: branch, token: token);

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) => GitHubTreeReader(client: _client, apiBase: _apiBase).readTree(
    owner: owner,
    repo: repo,
    branch: branch,
    headSha: headSha,
    token: token,
  );

  // --- Git Data: atomic incremental commit ---------------------------------

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
  }) =>
      GitHubCommitWriter(
        client: _client,
        apiBase: _apiBase,
        sleep: _sleep,
        clock: _clock,
      ).commit(
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

  // --- helpers -------------------------------------------------------------

  Future<http.Response> _get(Uri uri, {required Map<String, String> headers}) =>
      _guard(() => _client.get(uri, headers: headers));

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    Map<String, String>? body,
    Object? jsonBody,
  }) => _guard(() {
    if (jsonBody != null) {
      return _client.post(
        uri,
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(jsonBody),
      );
    }
    return _client.post(uri, headers: headers, body: body);
  });

  Future<http.Response> _guard(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on http.ClientException catch (e) {
      throw GitHubApiException(e.message);
    } on Exception catch (e) {
      throw GitHubApiException('$e');
    }
  }
}
