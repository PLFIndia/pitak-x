import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';

const _head = '1111111111111111111111111111111111111111';
const _baseTree = '2222222222222222222222222222222222222222';
const _newTree = '3333333333333333333333333333333333333333';
const _newCommit = '4444444444444444444444444444444444444444';
const _refRead = 'GET /repos/me/lib/git/ref/heads/main';
const _commitRead = 'GET /repos/me/lib/git/commits/$_head';

void main() {
  test('app-created repo publishes without bootstrap', () async {
    final fixture = _PublishFixture(
      intercept: (request) {
        if (_key(request) != 'POST /user/repos') return null;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'lib');
        expect(body['auto_init'], isTrue);
        return http.Response(jsonEncode({'default_branch': 'main'}), 201);
      },
    );
    final created = await fixture.api.createUserRepo(
      name: 'lib',
      token: 'test-token',
    );
    expect(created, isA<RepoCreated>());
    expect((created as RepoCreated).defaultBranch, 'main');
    final result = await fixture.publish();
    expect(result, isA<PublishCommitSuccess>());
    expect((result as PublishCommitSuccess).commitSha, _newCommit);
    expect(fixture.calls, [
      'POST /user/repos',
      _refRead,
      _commitRead,
      'POST /repos/me/lib/git/blobs',
      'POST /repos/me/lib/git/trees',
      'POST /repos/me/lib/git/commits',
      'PATCH /repos/me/lib/git/refs/heads/main',
    ]);
    final tree = jsonDecode(fixture.writes[2].body) as Map<String, dynamic>;
    // base_tree preserves README, CNAME, events.html and other unrelated paths.
    expect(tree['base_tree'], _baseTree);
    final commit = jsonDecode(fixture.writes[3].body) as Map<String, dynamic>;
    expect(commit['parents'], [_head]);
    expect(commit['tree'], _newTree);
    final ref = jsonDecode(fixture.writes.last.body) as Map<String, dynamic>;
    expect(ref, {'sha': _newCommit, 'force': false});
  });

  const writes = [
    'POST /repos/me/lib/git/blobs',
    'POST /repos/me/lib/git/trees',
    'POST /repos/me/lib/git/commits',
    'PATCH /repos/me/lib/git/refs/heads/main',
  ];
  for (final stage in writes) {
    test('write failure at $stage stops without further requests', () async {
      final status = stage.startsWith('PATCH') ? 422 : 500;
      final fixture = _PublishFixture(
        intercept: (request) =>
            _key(request) == stage ? http.Response('rejected', status) : null,
      );
      final result = await fixture.publish();
      expect(result, isA<PublishCommitHttpError>());
      expect((result as PublishCommitHttpError).code, status);
      expect(fixture.calls, [
        _refRead,
        _commitRead,
        ...writes.take(writes.indexOf(stage) + 1),
      ]);
      if (stage.startsWith('PATCH')) {
        final ref =
            jsonDecode(fixture.writes.last.body) as Map<String, dynamic>;
        expect(ref['force'], isFalse); // Never retry a conflict with force.
      }
    });
  }

  for (final files in <List<DesiredFile>>[
    [],
    [
      DesiredFile(
        path: 'books.json',
        bytes: const [],
        gitSha: GitBlobSha.of([1]),
        upload: false,
      ),
    ],
  ]) {
    test('preserves the base tree with ${files.length} cached files', () async {
      final fixture = _PublishFixture(intercept: (_) => null);
      final result = await fixture.publish(files: files);
      expect(result, isA<PublishCommitSuccess>());
      expect((result as PublishCommitSuccess).uploadedPaths, isEmpty);
      expect(fixture.calls, [
        _refRead,
        _commitRead,
        'POST /repos/me/lib/git/trees',
        'POST /repos/me/lib/git/commits',
        'PATCH /repos/me/lib/git/refs/heads/main',
      ]);
      final tree =
          jsonDecode(fixture.writes.first.body) as Map<String, dynamic>;
      expect(tree, {
        'base_tree': _baseTree,
        'tree': [
          for (final file in files)
            {
              'path': file.path,
              'mode': '100644',
              'type': 'blob',
              'sha': file.gitSha,
            },
        ],
      });
    });
  }

  for (final stage in {'ref': _refRead, 'commit': _commitRead}.entries) {
    for (final status in [201, 204, 302, 401, 403, 404, 409, 422, 429, 500]) {
      test('M01 ${stage.key} HTTP $status stops before all writes', () async {
        final fixture = _PublishFixture(
          intercept: (request) => _key(request) == stage.value
              ? http.Response('read failed', status)
              : null,
        );
        final result = await fixture.publish();
        expect(fixture.writes, isEmpty);
        expect(result, isA<PublishCommitHttpError>());
        expect((result as PublishCommitHttpError).code, status);
        expect(fixture.calls, [
          _refRead,
          if (stage.value == _commitRead) _commitRead,
        ]);
      });
    }
    for (final error in [
      http.ClientException('connection closed'),
      TimeoutException('request deadline'),
    ]) {
      test(
        'M01 ${stage.key} handles ${error.runtimeType} before writes',
        () async {
          final fixture = _PublishFixture(
            intercept: (request) {
              if (_key(request) == stage.value) throw error;
              return null;
            },
          );
          await expectLater(
            fixture.publish(),
            throwsA(isA<GitHubApiException>()),
          );
          expect(fixture.writes, isEmpty);
          expect(fixture.calls.last, stage.value);
        },
      );
    }
    final field = stage.key == 'ref' ? 'object' : 'tree';
    for (final malformed in _malformedBodies(field).entries) {
      test('M01 ${stage.key} rejects ${malformed.key} before writes', () async {
        final fixture = _PublishFixture(
          intercept: (request) => _key(request) == stage.value
              ? http.Response(malformed.value, 200)
              : null,
        );
        await expectLater(
          fixture.publish(),
          throwsA(
            isA<GitHubApiException>().having(
              (error) => error.message,
              'safe diagnostic',
              isNot(contains('private response')),
            ),
          ),
        );
        expect(fixture.writes, isEmpty);
        expect(fixture.calls, [
          _refRead,
          if (stage.value == _commitRead) _commitRead,
        ]);
      });
    }
  }
}

Map<String, String> _malformedBodies(String field) => {
  'invalid JSON': '<html>private response</html>',
  'non-object JSON': '[]',
  'null JSON': 'null',
  'missing $field': '{}',
  'null $field': jsonEncode({field: null}),
  'non-object $field': jsonEncode({field: 'private response'}),
  'missing sha': jsonEncode({field: <String, Object>{}}),
  for (final sha in <String, Object?>{
    'null': null,
    'numeric': 42,
    'empty': '',
    'blank': ' ',
    'short': 'a' * 39,
    'long': 'a' * 41,
    'non-hex': 'g' * 40,
    'newline': '${'a' * 39}\n',
    'suffix': '$_head\n',
    'path': '../other-commit',
  }.entries)
    '${sha.key} sha': jsonEncode({
      field: {'sha': sha.value},
    }),
};

String _key(http.Request request) => '${request.method} ${request.url.path}';

// Let every write succeed: an unsafe continuation must be caught by the test,
// not accidentally stopped by an unrelated mock failure.
final class _PublishFixture {
  _PublishFixture({required this.intercept});

  final http.Response? Function(http.Request) intercept;
  final requests = <http.Request>[];
  List<String> get calls => requests.map(_key).toList();
  List<http.Request> get writes =>
      requests.where((request) => request.method != 'GET').toList();

  late final api = HttpGitHubApi(
    client: MockClient((request) async {
      requests.add(request);
      return intercept(request) ?? _success(request);
    }),
    apiBase: Uri.parse('https://api.github.test'),
  );

  Future<PublishCommitResult> publish({List<DesiredFile>? files}) {
    return api.commitFiles(
      owner: 'me',
      repo: 'lib',
      branch: 'main',
      token: 'test-token',
      files:
          files ??
          [
            DesiredFile(
              path: 'books.json',
              bytes: const [1],
              gitSha: GitBlobSha.of([1]),
              upload: true,
            ),
          ],
      commitMessage: 'test publish',
    );
  }

  http.Response _success(http.Request request) {
    final (body, status) = switch (_key(request)) {
      _refRead => (
        {
          'object': {'sha': _head},
        },
        200,
      ),
      _commitRead => (
        {
          'tree': {'sha': _baseTree},
        },
        200,
      ),
      'POST /repos/me/lib/git/blobs' => (
        {
          'sha': GitBlobSha.of([1]),
        },
        201,
      ),
      'POST /repos/me/lib/git/trees' => ({'sha': _newTree}, 201),
      'POST /repos/me/lib/git/commits' => ({'sha': _newCommit}, 201),
      'PATCH /repos/me/lib/git/refs/heads/main' => (
        {'ref': 'refs/heads/main'},
        200,
      ),
      'POST /repos/me/lib/git/refs' => ({'ref': 'refs/heads/main'}, 201),
      _ => throw StateError('Unexpected test request: ${_key(request)}'),
    };
    return http.Response(jsonEncode(body), status);
  }
}
