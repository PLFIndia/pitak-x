/// HTTP implementation of [GitHubApi] (infrastructure, AGENTS.md §3.3, #32).
///
/// Ports the Kotlin GitHub stack (`GitHubAuthApi`, `GitHubContentsApi`,
/// `GitHubGitDataApi`, `GitTreePublisher`) into one cohesive client over
/// `http`. The Git Data flow is the atomic-incremental commit:
///   ref → blobs(changed only) → tree(base_tree + changed) → commit → move ref.
/// The branch ref moves exactly once at the end, so a failed publish leaves the
/// live page on its previous commit.
///
/// Auth host is github.com (device flow); API host is api.github.com. Tokens
/// are passed per-call as a Bearer header — an unauthenticated API call can't
/// be made by accident.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';

/// `http`-backed GitHub client.
final class HttpGitHubApi implements GitHubApi {
  /// Creates the client. [authBase]/[apiBase] are overridable for tests.
  HttpGitHubApi({required http.Client client, Uri? authBase, Uri? apiBase})
    : _client = client,
      _authBase = authBase ?? Uri.parse('https://github.com'),
      _apiBase = apiBase ?? Uri.parse('https://api.github.com');

  final http.Client _client;
  final Uri _authBase;
  final Uri _apiBase;

  static const String _accept = 'application/vnd.github+json';

  /// Git file mode for a normal (non-executable) blob.
  static const String _modeFile = '100644';

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
    final json = _decodeMap(resp.body);
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
    final json = _decodeMap(resp.body);
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
        throw GitHubApiException(
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
    final login = _decodeMap(resp.body)['login'] as String?;
    if (login == null) throw const GitHubApiException('No login in /user');
    return login;
  }

  @override
  Future<List<GitHubRepo>> userRepos(String token) async {
    final resp = await _get(
      _apiBase.replace(
        path: '/user/repos',
        queryParameters: {'per_page': '100', 'sort': 'updated'},
      ),
      headers: _authHeaders(token),
    );
    final list = jsonDecode(resp.body);
    if (list is! List) throw const GitHubApiException('Malformed repo list');
    return [
      for (final e in list.whereType<Map<String, dynamic>>())
        if (e['full_name'] is String)
          GitHubRepo(
            fullName: e['full_name'] as String,
            isPrivate: (e['private'] as bool?) ?? false,
            htmlUrl: e['html_url'] as String?,
          ),
    ];
  }

  @override
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final resp = await _client.get(
      _apiBase.replace(path: '/repos/$owner/$repo'),
      headers: _authHeaders(token),
    );
    if (resp.statusCode >= 400) return null;
    return _decodeMap(resp.body)['default_branch'] as String?;
  }

  // --- Git Data: read head tree (manifest rebuild) -------------------------

  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    final headSha = await _refSha(owner, repo, branch, token);
    if (headSha == null) return {};
    final treeSha = await _commitTreeSha(owner, repo, headSha, token);
    if (treeSha == null) return {};
    final resp = await _client.get(
      _apiBase.replace(
        path: '/repos/$owner/$repo/git/trees/$treeSha',
        queryParameters: {'recursive': '1'},
      ),
      headers: _authHeaders(token),
    );
    if (resp.statusCode >= 400) return {};
    final tree = _decodeMap(resp.body)['tree'];
    if (tree is! List) return {};
    return {
      for (final e in tree.whereType<Map<String, dynamic>>())
        if (e['type'] == 'blob' && e['path'] is String && e['sha'] is String)
          e['path'] as String: e['sha'] as String,
    };
  }

  // --- Git Data: atomic incremental commit ---------------------------------

  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
  }) async {
    final headers = _authHeaders(token);

    // 1. Current head + its base tree. 404/409 → empty repo (bootstrap).
    String? headSha;
    final refResp = await _client.get(
      _apiBase.replace(path: '/repos/$owner/$repo/git/ref/heads/$branch'),
      headers: headers,
    );
    if (refResp.statusCode == 200) {
      headSha = (_decodeMap(refResp.body)['object'] as Map?)?['sha'] as String?;
    } else if (refResp.statusCode != 404 && refResp.statusCode != 409) {
      return PublishCommitHttpError(refResp.statusCode, _excerpt(refResp.body));
    }
    String? baseTreeSha;
    if (headSha != null) {
      baseTreeSha = await _commitTreeSha(owner, repo, headSha, token);
    }

    // 2. Upload changed blobs (serially — simple + safe; counts are small).
    for (final f in files.where((f) => f.upload)) {
      final blobResp = await _post(
        _apiBase.replace(path: '/repos/$owner/$repo/git/blobs'),
        headers: headers,
        jsonBody: {'content': base64Encode(f.bytes), 'encoding': 'base64'},
      );
      if (blobResp.statusCode >= 400) {
        return PublishCommitHttpError(
          blobResp.statusCode,
          _excerpt(blobResp.body),
        );
      }
    }

    // 3. New tree: every desired file as an entry, by sha.
    final treeEntries = [
      for (final f in files)
        {'path': f.path, 'mode': _modeFile, 'type': 'blob', 'sha': f.gitSha},
    ];
    final treeResp = await _post(
      _apiBase.replace(path: '/repos/$owner/$repo/git/trees'),
      headers: headers,
      jsonBody: {
        if (baseTreeSha != null) 'base_tree': baseTreeSha,
        'tree': treeEntries,
      },
    );
    if (treeResp.statusCode >= 400) {
      return PublishCommitHttpError(
        treeResp.statusCode,
        _excerpt(treeResp.body),
      );
    }
    final newTreeSha = _decodeMap(treeResp.body)['sha'] as String?;
    if (newTreeSha == null) {
      return PublishCommitHttpError(treeResp.statusCode, 'Empty tree sha');
    }

    // 4. Commit pointing at the new tree.
    final commitResp = await _post(
      _apiBase.replace(path: '/repos/$owner/$repo/git/commits'),
      headers: headers,
      jsonBody: {
        'message': commitMessage,
        'tree': newTreeSha,
        'parents': headSha != null ? [headSha] : <String>[],
      },
    );
    if (commitResp.statusCode >= 400) {
      return PublishCommitHttpError(
        commitResp.statusCode,
        _excerpt(commitResp.body),
      );
    }
    final newCommitSha = _decodeMap(commitResp.body)['sha'] as String?;
    if (newCommitSha == null) {
      return PublishCommitHttpError(commitResp.statusCode, 'Empty commit sha');
    }

    // 5. Move (or create) the branch ref — the single atomic flip.
    final http.Response refMove;
    if (headSha != null) {
      refMove = await _patch(
        _apiBase.replace(path: '/repos/$owner/$repo/git/refs/heads/$branch'),
        headers: headers,
        jsonBody: {'sha': newCommitSha, 'force': false},
      );
    } else {
      refMove = await _post(
        _apiBase.replace(path: '/repos/$owner/$repo/git/refs'),
        headers: headers,
        jsonBody: {'ref': 'refs/heads/$branch', 'sha': newCommitSha},
      );
    }
    if (refMove.statusCode >= 400) {
      return PublishCommitHttpError(refMove.statusCode, _excerpt(refMove.body));
    }

    return PublishCommitSuccess(newCommitSha, [
      for (final f in files.where((f) => f.upload)) f.path,
    ]);
  }

  @override
  Future<bool?> latestPagesBuildStatus({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final resp = await _client.get(
      _apiBase.replace(path: '/repos/$owner/$repo/pages/builds/latest'),
      headers: _authHeaders(token),
    );
    if (resp.statusCode >= 400) return null; // no Pages scope / not found
    final status = _decodeMap(resp.body)['status'] as String?;
    return switch (status) {
      'built' => true,
      'errored' => false,
      _ => null,
    };
  }

  // --- helpers -------------------------------------------------------------

  Future<String?> _refSha(
    String owner,
    String repo,
    String branch,
    String token,
  ) async {
    final resp = await _client.get(
      _apiBase.replace(path: '/repos/$owner/$repo/git/ref/heads/$branch'),
      headers: _authHeaders(token),
    );
    if (resp.statusCode >= 400) return null;
    return (_decodeMap(resp.body)['object'] as Map?)?['sha'] as String?;
  }

  Future<String?> _commitTreeSha(
    String owner,
    String repo,
    String commitSha,
    String token,
  ) async {
    final resp = await _client.get(
      _apiBase.replace(path: '/repos/$owner/$repo/git/commits/$commitSha'),
      headers: _authHeaders(token),
    );
    if (resp.statusCode >= 400) return null;
    return (_decodeMap(resp.body)['tree'] as Map?)?['sha'] as String?;
  }

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

  Future<http.Response> _patch(
    Uri uri, {
    required Map<String, String> headers,
    required Object jsonBody,
  }) => _guard(
    () => _client.patch(
      uri,
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(jsonBody),
    ),
  );

  Future<http.Response> _guard(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on http.ClientException catch (e) {
      throw GitHubApiException(e.message);
    } on Exception catch (e) {
      throw GitHubApiException('$e');
    }
  }

  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const GitHubApiException('Expected a JSON object');
    }
    return decoded;
  }

  String _excerpt(String body) =>
      body.length <= 200 ? body : body.substring(0, 200);
}
