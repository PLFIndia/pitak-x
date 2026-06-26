import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';

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
                'object': {'sha': 'HEADSHA'},
              }),
              200,
            );
          }
          if (p.endsWith('/git/commits/HEADSHA')) {
            return http.Response(
              jsonEncode({
                'tree': {'sha': 'BASETREE'},
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
            expect(body['base_tree'], 'BASETREE');
            return http.Response(jsonEncode({'sha': 'NEWTREE'}), 201);
          }
          if (p.endsWith('/git/commits')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['tree'], 'NEWTREE');
            expect(body['parents'], ['HEADSHA']);
            return http.Response(jsonEncode({'sha': 'NEWCOMMIT'}), 201);
          }
          if (p.endsWith('/git/refs/heads/main')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['sha'], 'NEWCOMMIT');
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

    test('empty repo (404 ref) bootstraps via createRef', () async {
      final bytes = utf8.encode('x');
      final sha = GitBlobSha.of(bytes);
      var createdRef = false;
      final svc = api(
        MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/git/ref/heads/main')) return http.Response('', 404);
          if (p.endsWith('/git/blobs')) {
            return http.Response(jsonEncode({'sha': sha}), 201);
          }
          if (p.endsWith('/git/trees')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            // No base_tree on an empty repo.
            expect(body.containsKey('base_tree'), isFalse);
            return http.Response(jsonEncode({'sha': 'T'}), 201);
          }
          if (p.endsWith('/git/commits')) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['parents'], isEmpty);
            return http.Response(jsonEncode({'sha': 'C'}), 201);
          }
          if (p.endsWith('/git/refs')) {
            createdRef = true;
            return http.Response(jsonEncode({'ref': 'refs/heads/main'}), 201);
          }
          return http.Response('unexpected', 500);
        }),
      );
      final result = await svc.commitFiles(
        owner: 'me',
        repo: 'lib',
        branch: 'main',
        token: 'TKN',
        files: [
          DesiredFile(path: 'x', bytes: bytes, gitSha: sha, upload: true),
        ],
        commitMessage: 'init',
      );
      expect(result, isA<PublishCommitSuccess>());
      expect(createdRef, isTrue);
    });

    test('an HTTP error before the ref move returns HttpError', () async {
      final svc = api(
        MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/git/ref/heads/main')) {
            return http.Response(
              jsonEncode({
                'object': {'sha': 'H'},
              }),
              200,
            );
          }
          if (p.endsWith('/git/commits/H')) {
            return http.Response(
              jsonEncode({
                'tree': {'sha': 'BT'},
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
