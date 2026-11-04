import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';

/// Review finding 2: a GitHub redirect must never be followed.
///
/// These tests use a REAL loopback HTTP server and the REAL `IOClient`
/// (never GitHub): `package:http`'s redirect handling is implemented by the
/// client, so a fake client cannot prove it is disabled. Every address is
/// 127.0.0.1.
void main() {
  const headSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const baseTreeSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const newTreeSha = 'cccccccccccccccccccccccccccccccccccccccc';
  const newCommitSha = 'dddddddddddddddddddddddddddddddddddddddd';

  late _Loopback loopback;
  late http.Client client;

  setUp(() async {
    loopback = await _Loopback.start();
    client = IOClient(HttpClient());
    addTearDown(client.close);
    addTearDown(loopback.close);
  });

  HttpGitHubApi api() => HttpGitHubApi(
    client: client,
    authBase: loopback.base,
    apiBase: loopback.base,
  );

  test('GET: a 302 is refused, the target is never requested', () async {
    // The target would answer a perfectly valid 200: only the refusal stops
    // it from being read as this account's answer.
    loopback.onRequest = (request) => request.uri.path == '/target'
        ? loopback.json(request, {'login': 'someone-else'})
        : loopback.redirect(request, '/target');

    await expectLater(
      api().currentUserLogin('token'),
      throwsA(
        isA<GitHubApiException>().having(
          (e) => e.message,
          'message',
          contains('redirect'),
        ),
      ),
    );
    expect(loopback.requests, ['GET /user']);
  });

  test('POST: a 302 is refused, the target is never requested', () async {
    // `enablePages` is the POST where a 3xx used to pass silently: its check
    // only rejects statuses above 399, so "no error" could mean "redirect".
    loopback.onRequest = (request) => request.uri.path == '/target'
        ? loopback.json(request, {})
        : loopback.redirect(request, '/target');

    await expectLater(
      api().enablePages(
        owner: 'me',
        repo: 'lib',
        branch: 'main',
        token: 'token',
      ),
      throwsA(isA<GitHubApiException>()),
    );
    expect(loopback.requests, ['POST /repos/me/lib/pages']);
  });

  test(
    'PATCH: a 302 on the single ref move is refused, not followed',
    () async {
      // The whole Git Data flow runs against the loopback server so the PATCH
      // goes through its public entry point (`commitFiles`). Only the ref move
      // answers 302.
      loopback.onRequest = (request) async {
        final path = request.uri.path;
        if (request.method == 'GET' && path.endsWith('/git/ref/heads/main')) {
          return loopback.json(request, {
            'object': {'sha': headSha},
          });
        }
        if (request.method == 'GET' && path.contains('/git/commits/')) {
          return loopback.json(request, {
            'tree': {'sha': baseTreeSha},
          });
        }
        if (request.method == 'POST' && path.endsWith('/git/trees')) {
          return loopback.json(request, {'sha': newTreeSha});
        }
        if (request.method == 'POST' && path.endsWith('/git/commits')) {
          return loopback.json(request, {'sha': newCommitSha});
        }
        if (path == '/target') {
          return loopback.json(request, {});
        }
        if (request.method == 'PATCH' &&
            path.endsWith('/git/refs/heads/main')) {
          return loopback.redirect(request, '/target');
        }
        return loopback.json(request, {'message': 'unexpected'}, status: 500);
      };

      await expectLater(
        api().commitFiles(
          owner: 'me',
          repo: 'lib',
          branch: 'main',
          token: 'token',
          plan: GitHubCommitPlan(files: const [], knownBlobShas: const {}),
          commitMessage: 'Pitaka publish',
          expectedHead: headSha,
        ),
        throwsA(isA<GitHubApiException>()),
      );
      expect(loopback.requests, [
        'GET /repos/me/lib/git/ref/heads/main',
        'GET /repos/me/lib/git/commits/$headSha',
        'POST /repos/me/lib/git/trees',
        'POST /repos/me/lib/git/commits',
        'PATCH /repos/me/lib/git/refs/heads/main',
      ]);
    },
  );

  test('an ordinary 200 answer still works through the same client', () async {
    loopback.onRequest = (request) => loopback.json(request, {'login': 'me'});

    expect(await api().currentUserLogin('token'), 'me');
  });
}

/// One real loopback server whose answer the test decides per request.
final class _Loopback {
  _Loopback._(this._server);

  final HttpServer _server;

  /// Every request, as "METHOD path" — the proof that nothing was followed.
  final List<String> requests = [];

  /// Answers one request. Throws are ignored (the connection may already be
  /// gone when a test refuses a response body).
  late Future<void> Function(HttpRequest request) onRequest;

  static Future<_Loopback> start() async {
    final loopback = _Loopback._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    loopback._server.listen((request) {
      loopback.requests.add('${request.method} ${request.uri.path}');
      unawaited(
        loopback.onRequest(request).catchError((Object _) {
          // The client closing early is expected: refusing a redirect body
          // is exactly what the production client does.
        }),
      );
    });
    return loopback;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);

  Future<void> json(
    HttpRequest request,
    Object body, {
    int status = 200,
  }) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> redirect(HttpRequest request, String location) async {
    request.response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, '$base$location');
    await request.response.close();
  }
}
