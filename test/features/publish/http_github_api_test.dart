import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';

const _headSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _baseTreeSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  HttpGitHubApi api(MockClient c) => HttpGitHubApi(
    client: c,
    authBase: Uri.parse('https://github.test'),
    apiBase: Uri.parse('https://api.github.test'),
  );

  group('device flow', () {
    test('requestDeviceCode parses the grant', () async {
      final svc = api(
        MockClient((req) async {
          expect(req.url.path, '/login/device/code');
          return http.Response(
            jsonEncode({
              'device_code': 'DC',
              'user_code': 'WXYZ-1234',
              'verification_uri': 'https://github.test/login/device',
              'expires_in': 900,
              'interval': 5,
            }),
            200,
          );
        }),
      );
      final grant = await svc.requestDeviceCode(
        clientId: 'cid',
        scope: 'public_repo',
      );
      expect(grant.userCode, 'WXYZ-1234');
      expect(grant.deviceCode, 'DC');
    });

    test('pollAccessToken maps pending/denied/authorized', () async {
      // Assert each response shape with its own client.
      expect(
        await api(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'error': 'authorization_pending'}),
              200,
            ),
          ),
        ).pollAccessToken(clientId: 'c', deviceCode: 'd'),
        isA<PollPending>(),
      );
      expect(
        await api(
          MockClient(
            (_) async =>
                http.Response(jsonEncode({'error': 'access_denied'}), 200),
          ),
        ).pollAccessToken(clientId: 'c', deviceCode: 'd'),
        isA<PollDenied>(),
      );
      final ok = await api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'access_token': 'TKN', 'scope': 'public_repo'}),
            200,
          ),
        ),
      ).pollAccessToken(clientId: 'c', deviceCode: 'd');
      expect(ok, isA<PollAuthorized>());
      expect((ok as PollAuthorized).accessToken, 'TKN');
    });

    test(
      'pollAccessToken maps unknown protocol errors to PollFatal, not throw '
      '(thrown = transient/retryable; a dead grant must not be retried)',
      () async {
        final r = await api(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': 'device_flow_disabled',
                'error_description': 'Device flow is disabled for this app',
              }),
              200,
            ),
          ),
        ).pollAccessToken(clientId: 'c', deviceCode: 'd');
        expect(r, isA<PollFatal>());
      },
    );
  });

  group('repo setup endpoints', () {
    test(
      'createUserRepo posts auto_init+public and parses the branch',
      () async {
        late Map<String, dynamic> sent;
        final svc = api(
          MockClient((req) async {
            expect(req.url.path, '/user/repos');
            expect(req.headers['Authorization'], 'Bearer tok');
            sent = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'default_branch': 'main'}), 201);
          }),
        );
        final r = await svc.createUserRepo(name: 'my-library', token: 'tok');
        expect(r, isA<RepoCreated>());
        expect((r as RepoCreated).defaultBranch, 'main');
        expect(sent['name'], 'my-library');
        expect(sent['auto_init'], isTrue);
        expect(sent['private'], isFalse);
      },
    );

    test('createUserRepo maps 422 to RepoAlreadyExists', () async {
      final svc = api(
        MockClient(
          (req) async => http.Response(
            jsonEncode({'message': 'name already exists on this account'}),
            422,
          ),
        ),
      );
      final r = await svc.createUserRepo(name: 'x', token: 'tok');
      expect(r, isA<RepoAlreadyExists>());
    });

    test('createUserRepo throws on other HTTP errors', () async {
      final svc = api(
        MockClient(
          (req) async =>
              http.Response(jsonEncode({'message': 'Bad credentials'}), 401),
        ),
      );
      expect(
        () => svc.createUserRepo(name: 'x', token: 'bad'),
        throwsA(isA<GitHubApiException>()),
      );
    });

    test(
      'enablePages posts the branch source; 409 counts as success',
      () async {
        var calls = 0;
        final svc = api(
          MockClient((req) async {
            calls++;
            expect(req.url.path, '/repos/o/r/pages');
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect((body['source'] as Map)['branch'], 'main');
            // First call: created. Second call: already enabled.
            return http.Response(
              calls == 1 ? '{}' : jsonEncode({'message': 'already enabled'}),
              calls == 1 ? 201 : 409,
            );
          }),
        );
        await svc.enablePages(
          owner: 'o',
          repo: 'r',
          branch: 'main',
          token: 't',
        );
        await svc.enablePages(
          owner: 'o',
          repo: 'r',
          branch: 'main',
          token: 't',
        );
        expect(calls, 2); // both completed without throwing
      },
    );

    test('enablePages throws on a real error', () async {
      final svc = api(
        MockClient(
          (req) async =>
              http.Response(jsonEncode({'message': 'forbidden'}), 403),
        ),
      );
      expect(
        () =>
            svc.enablePages(owner: 'o', repo: 'r', branch: 'main', token: 't'),
        throwsA(isA<GitHubApiException>()),
      );
    });
  });

  group('commitFiles (Git Data atomic flow)', () {
    test('blobs → tree → commit → updateRef on a non-empty repo', () async {
      final calls = <String>[];
      final bytes = utf8.encode('{"books":[]}');
      final sha = GitBlobSha.of(bytes);

      final svc = api(
        MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          final p = req.url.path;
          if (p.endsWith('/git/ref/heads/main')) {
            return http.Response(
              jsonEncode({
                'object': {'sha': _headSha},
              }),
              200,
            );
          }
          if (p.endsWith('/git/commits/$_headSha')) {
            return http.Response(
              jsonEncode({
                'tree': {'sha': _baseTreeSha},
              }),
              200,
            );
          }
          if (p.endsWith('/git/blobs')) {
            return http.Response(jsonEncode({'sha': sha}), 201);
          }
          if (p.endsWith('/git/trees')) {
            // base_tree must be threaded through.
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['base_tree'], _baseTreeSha);
            return http.Response(jsonEncode({'sha': 'NEWTREE'}), 201);
          }
          if (p.endsWith('/git/commits')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['tree'], 'NEWTREE');
            expect(body['parents'], [_headSha]);
            return http.Response(jsonEncode({'sha': 'NEWCOMMIT'}), 201);
          }
          if (p.endsWith('/git/refs/heads/main')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['sha'], 'NEWCOMMIT');
            expect(body['force'], isFalse);
            return http.Response(jsonEncode({'ref': 'refs/heads/main'}), 200);
          }
          return http.Response('unexpected ${req.url.path}', 500);
        }),
      );

      final result = await svc.commitFiles(
        owner: 'me',
        repo: 'lib',
        branch: 'main',
        token: 'TKN',
        files: [
          DesiredFile(
            path: 'books.json',
            bytes: bytes,
            gitSha: sha,
            upload: true,
          ),
        ],
        commitMessage: 'Pitaka publish',
      );

      expect(result, isA<PublishCommitSuccess>());
      expect((result as PublishCommitSuccess).commitSha, 'NEWCOMMIT');
      expect(result.uploadedPaths, ['books.json']);
      // The ref move (PATCH) happened last.
      expect(calls.last, 'PATCH /repos/me/lib/git/refs/heads/main');
    });

    // M14: obsolete app-owned paths ride in the SAME atomic commit as tree
    // entries whose sha is null — GitHub's documented delete form.
    test(
      'deletePaths become null-sha tree entries in the same commit',
      () async {
        final bytes = utf8.encode('<html></html>');
        final sha = GitBlobSha.of(bytes);
        List<Map<String, dynamic>>? sentTree;

        final svc = api(
          MockClient((req) async {
            final p = req.url.path;
            if (p.endsWith('/git/ref/heads/main')) {
              return http.Response(
                jsonEncode({
                  'object': {'sha': _headSha},
                }),
                200,
              );
            }
            if (p.endsWith('/git/commits/$_headSha')) {
              return http.Response(
                jsonEncode({
                  'tree': {'sha': _baseTreeSha},
                }),
                200,
              );
            }
            if (p.endsWith('/git/blobs')) {
              return http.Response(jsonEncode({'sha': sha}), 201);
            }
            if (p.endsWith('/git/trees')) {
              final body = jsonDecode(req.body) as Map<String, dynamic>;
              sentTree = (body['tree'] as List).cast<Map<String, dynamic>>();
              return http.Response(jsonEncode({'sha': 'NEWTREE'}), 201);
            }
            if (p.endsWith('/git/commits')) {
              return http.Response(jsonEncode({'sha': 'NEWCOMMIT'}), 201);
            }
            if (p.endsWith('/git/refs/heads/main')) {
              return http.Response(jsonEncode({'ref': 'refs/heads/main'}), 200);
            }
            return http.Response('unexpected ${req.url.path}', 500);
          }),
        );

        final result = await svc.commitFiles(
          owner: 'me',
          repo: 'lib',
          branch: 'main',
          token: 'TKN',
          files: [
            DesiredFile(
              path: 'events.html',
              bytes: bytes,
              gitSha: sha,
              upload: true,
            ),
          ],
          commitMessage: 'Pitaka events publish',
          deletePaths: const ['posters/old.jpg'],
        );

        expect(result, isA<PublishCommitSuccess>());
        expect(sentTree, isNotNull);
        // The kept file carries its sha; the deleted path carries null.
        final byPath = {for (final e in sentTree!) e['path'] as String: e};
        expect(byPath['events.html']!['sha'], sha);
        expect(byPath['posters/old.jpg']!['sha'], isNull);
      },
    );

    test('missing ref fails without trying to initialize a repo', () async {
      final calls = <String>[];
      final svc = api(
        MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          return http.Response('', 404);
        }),
      );
      final result = await svc.commitFiles(
        owner: 'me',
        repo: 'lib',
        branch: 'main',
        token: 'TKN',
        files: const [],
        commitMessage: 'publish',
      );
      expect(result, isA<PublishCommitHttpError>());
      expect((result as PublishCommitHttpError).code, 404);
      expect(calls, ['GET /repos/me/lib/git/ref/heads/main']);
    });

    test('an HTTP error before the ref move returns HttpError', () async {
      final svc = api(
        MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/git/ref/heads/main')) {
            return http.Response(
              jsonEncode({
                'object': {'sha': _headSha},
              }),
              200,
            );
          }
          if (p.endsWith('/git/commits/$_headSha')) {
            return http.Response(
              jsonEncode({
                'tree': {'sha': _baseTreeSha},
              }),
              200,
            );
          }
          if (p.endsWith('/git/blobs')) return http.Response('rate limit', 403);
          return http.Response('unexpected', 500);
        }),
      );
      final result = await svc.commitFiles(
        owner: 'me',
        repo: 'lib',
        branch: 'main',
        token: 'TKN',
        files: [
          const DesiredFile(
            path: 'x',
            bytes: [1],
            gitSha: 'deadbeef',
            upload: true,
          ),
        ],
        commitMessage: 'm',
      );
      expect(result, isA<PublishCommitHttpError>());
      expect((result as PublishCommitHttpError).code, 403);
    });
  });
}
