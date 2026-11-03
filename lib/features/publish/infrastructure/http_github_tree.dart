/// Reads one branch's head commit and recursive tree (infrastructure;
/// Cloudflare plan R6).
///
/// Why its own class (beginner note): the publish flow needs a *typed,
/// complete* snapshot of the remote site before it can decide what it may
/// upload or delete. The commit adapter's job is writing; reading the state
/// it plans against is a different responsibility with a different failure
/// rule, so it lives here rather than growing that class past its size limit.
///
/// Every read that cannot be trusted throws [GitHubApiException] — a missing
/// branch, an HTTP error, a malformed body. It never answers with an empty or
/// partial map: "I could not read the site" and "the site is empty" must not be
/// the same value, because the second one permits a destructive publish.
///
/// Two steps, two methods (plan SP4): `readHead` asks which commit the branch
/// points at (one small request), and `readTree` reads that commit's complete
/// file list (two requests, the second one large). Splitting them lets the
/// caller skip the large read when the head is a commit it already knows —
/// the decision itself lives in the domain (`PublishManifest`), not here.
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/infrastructure/github_http_support.dart';

/// Reads `<apiBase>/repos/...` Git Data state for a publish.
final class GitHubTreeReader {
  /// Creates the reader over the shared HTTP client.
  const GitHubTreeReader({required http.Client client, required Uri apiBase})
    : _client = client,
      _apiBase = apiBase;

  final http.Client _client;
  final Uri _apiBase;

  static const String _accept = 'application/vnd.github+json';

  /// Reads the commit sha [branch] points at now (one request).
  Future<String> readHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    if (!GitHubBranchName.isValid(branch)) {
      throw const GitHubApiException('Unsafe branch name');
    }
    final ref = await _get(
      '/repos/$owner/$repo/git/ref/heads/$branch',
      _headers(token),
    );
    if (ref.statusCode != 200) {
      // Setup creates repos with auto_init, so a branch the app cannot read
      // means the site state is UNKNOWN — never "nothing is published" (R6).
      throw GitHubApiException('head ref: HTTP ${ref.statusCode}');
    }
    return gitHubObjectSha(ref.body, 'object');
  }

  /// Reads the full recursive blob map of commit [headSha] on [branch].
  ///
  /// [headSha] must be a 40-hex commit sha (normally [readHead]'s answer); it
  /// becomes part of a request path, so anything else is refused before a
  /// request is made.
  Future<GitHubTreeSnapshot> readTree({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) async {
    if (!GitHubBranchName.isValid(branch)) {
      throw const GitHubApiException('Unsafe branch name');
    }
    if (!gitHubShaPattern.hasMatch(headSha)) {
      throw const GitHubApiException('Malformed Git object SHA');
    }
    final headers = _headers(token);

    final commit = await _get(
      '/repos/$owner/$repo/git/commits/$headSha',
      headers,
    );
    if (commit.statusCode != 200) {
      throw GitHubApiException('head commit: HTTP ${commit.statusCode}');
    }
    final treeSha = gitHubObjectSha(commit.body, 'tree');

    final resp = await _get(
      '/repos/$owner/$repo/git/trees/$treeSha',
      headers,
      query: {'recursive': '1'},
    );
    if (resp.statusCode != 200) {
      throw GitHubApiException('tree: HTTP ${resp.statusCode}');
    }
    final decoded = decodeGitHubObject(resp.body);
    final tree = decoded['tree'];
    if (tree is! List) throw const GitHubApiException('Malformed tree');
    final files = <String, String>{};
    for (final entry in tree.whereType<Map<String, dynamic>>()) {
      final path = entry['path'];
      final sha = entry['sha'];
      // Only blobs are files: a directory or a submodule commit entry is not
      // publishable content and must never enter the record.
      if (entry['type'] == 'blob' && path is String && sha is String) {
        files[path] = sha;
      }
    }
    return GitHubTreeSnapshot(
      repo: '$owner/$repo',
      branch: branch,
      headSha: headSha,
      files: files,
      truncated: decoded['truncated'] == true,
    );
  }

  static Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': _accept,
  };

  Future<http.Response> _get(
    String path,
    Map<String, String> headers, {
    Map<String, String>? query,
  }) async {
    final uri = _apiBase.replace(path: path, queryParameters: query);
    try {
      return await _client.get(uri, headers: headers);
    } on Exception {
      // Transport detail (URL, socket text) stays out of the diagnostic.
      throw const GitHubApiException('tree read failed');
    }
  }
}
