import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';

/// A small in-memory model of GitHub's Git Data API for ONE repository
/// (`me/lib`, branch `main`), behind a [MockClient] (plan J8 tests).
///
/// It keeps the two facts the J8 fix relies on, both checked against the
/// real API (plan A.6 #100):
///  - a blob, once created, stays in the repository and any later tree may
///    name it, even when no tree referenced it before;
///  - a tree naming a sha the repository does not hold is refused with 422.
///
/// [acceptBlobs] makes it answer like GitHub's content limit: after that
/// many accepted blob requests it refuses the next ones with [refusal]
/// until a test sets it again (null = no limit).
final class FakeGitHubGitServer {
  /// Creates the server with [files] (path → bytes) already committed.
  FakeGitHubGitServer({Map<String, List<int>> files = const {}}) {
    for (final entry in files.entries) {
      final sha = GitBlobSha.of(entry.value);
      objects.add(sha);
      headFiles[entry.key] = sha;
    }
    _trees[_treeSha(0)] = Map.of(headFiles);
    _commitTree[head] = _treeSha(0);
  }

  /// Every blob sha the repository holds (committed or not).
  final Set<String> objects = {};

  /// The head tree: path → blob sha.
  Map<String, String> headFiles = {};

  /// The head commit.
  String head = _commitSha(0);

  /// How many more blob requests are accepted; null = no limit.
  int? acceptBlobs;

  /// The answer once [acceptBlobs] is used up: GitHub's secondary limit.
  http.Response Function() refusal = () => http.Response(
    jsonEncode({
      'message':
          'You have exceeded a secondary rate limit and have been temporarily '
          'blocked from content creation. Please retry your request again '
          'later.',
    }),
    403,
  );

  /// Called before each blob request is answered (a test can advance a
  /// clock or throw a transport error here).
  void Function(int blobRequest)? beforeBlob;

  /// Counters for the requests that create content.
  int blobRequests = 0;
  int acceptedBlobs = 0;
  int treeRequests = 0;
  int commitRequests = 0;
  int refMoves = 0;

  /// Every request, as "METHOD path".
  final List<String> log = [];

  final Map<String, Map<String, String>> _trees = {};
  final Map<String, String> _commitTree = {};
  int _counter = 0;

  static String _treeSha(int n) => 'd${n.toString().padLeft(39, '0')}';
  static String _commitSha(int n) => 'c${n.toString().padLeft(39, '0')}';

  /// The client to give `HttpGitHubApi`.
  MockClient get client => MockClient(handle);

  /// Answers one request (a test's own [MockClient] can fall back to it).
  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    log.add('${req.method} $path');
    if (!path.startsWith('/repos/me/lib/git/')) {
      return http.Response('unexpected $path', 500);
    }
    final rest = path.substring('/repos/me/lib/git/'.length);
    if (req.method == 'GET' && rest == 'ref/heads/main') {
      return _json({
        'object': {'sha': head},
      }, 200);
    }
    if (req.method == 'GET' && rest.startsWith('commits/')) {
      final tree = _commitTree[rest.substring('commits/'.length)];
      if (tree == null) return http.Response('{"message":"Not Found"}', 404);
      return _json({
        'tree': {'sha': tree},
      }, 200);
    }
    final body = req.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(req.body) as Map<String, dynamic>;
    if (req.method == 'POST' && rest == 'blobs') {
      blobRequests++;
      beforeBlob?.call(blobRequests);
      final left = acceptBlobs;
      if (left != null) {
        if (left <= 0) return refusal();
        acceptBlobs = left - 1;
      }
      final bytes = base64Decode(body['content'] as String);
      final sha = GitBlobSha.of(bytes);
      objects.add(sha);
      acceptedBlobs++;
      return _json({'sha': sha}, 201);
    }
    if (req.method == 'POST' && rest == 'trees') {
      treeRequests++;
      final base = _trees[body['base_tree']];
      if (base == null) return http.Response('{"message":"bad base"}', 422);
      final files = Map.of(base);
      for (final entry in (body['tree'] as List).cast<Map<String, dynamic>>()) {
        final sha = entry['sha'] as String?;
        final entryPath = entry['path'] as String;
        if (sha == null) {
          files.remove(entryPath);
        } else if (!objects.contains(sha)) {
          return _json({'message': 'tree.sha $sha is not a valid blob'}, 422);
        } else {
          files[entryPath] = sha;
        }
      }
      final sha = _treeSha(++_counter);
      _trees[sha] = files;
      return _json({'sha': sha}, 201);
    }
    if (req.method == 'POST' && rest == 'commits') {
      commitRequests++;
      final sha = _commitSha(++_counter);
      _commitTree[sha] = body['tree'] as String;
      return _json({'sha': sha}, 201);
    }
    if (req.method == 'PATCH' && rest == 'refs/heads/main') {
      refMoves++;
      final commit = body['sha'] as String;
      head = commit;
      headFiles = Map.of(_trees[_commitTree[commit]]!);
      return _json({'ref': 'refs/heads/main'}, 200);
    }
    return http.Response('unexpected ${req.method} $path', 500);
  }

  static http.Response _json(Object body, int status) =>
      http.Response(jsonEncode(body), status);
}
