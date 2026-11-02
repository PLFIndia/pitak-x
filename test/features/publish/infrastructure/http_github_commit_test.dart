import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';

import '../support/fake_github_git_server.dart';

/// Plan J8 in the HTTP adapter (`GitHubCommitWriter` behind
/// `HttpGitHubApi.commitFiles`): pacing (b), recognising GitHub's rate-limit
/// answer, and reporting each blob GitHub confirmed storing (a).
void main() {
  const t0 = 1_800_000_000_000;

  PublishFile file(String path, String content) {
    final bytes = utf8.encode(content);
    return PublishFile(
      path: path,
      bytes: bytes,
      gitSha: GitBlobSha.of(bytes),
      upload: true,
    );
  }

  String sha(String content) => GitBlobSha.of(utf8.encode(content));

  GitHubCommitPlan plan(int files) => GitHubCommitPlan(
    files: [for (var n = 1; n <= files; n++) file('covers/$n.jpg', 'cover $n')],
    knownBlobShas: const {},
  );

  /// A clock that only moves when the adapter sleeps or a test moves it.
  late int now;
  late List<Duration> sleeps;

  setUp(() {
    now = t0;
    sleeps = [];
  });

  HttpGitHubApi api(http.Client client) => HttpGitHubApi(
    client: client,
    apiBase: Uri.parse('https://api.github.test'),
    clock: () => now,
    sleep: (d) async {
      sleeps.add(d);
      now += d.inMilliseconds;
    },
  );

  Future<PublishCommitResult> commit(
    HttpGitHubApi github,
    GitHubCommitPlan planned, {
    String head = '',
    Future<void> Function(String)? onBlobStored,
  }) => github.commitFiles(
    owner: 'me',
    repo: 'lib',
    branch: 'main',
    token: 'TKN',
    plan: planned,
    commitMessage: 'test',
    expectedHead: head,
    onBlobStored: onBlobStored,
  );

  group('pacing (J8 b)', () {
    test('blob requests start at least one second apart', () async {
      final server = FakeGitHubGitServer();
      final result = await commit(
        api(server.client),
        plan(3),
        head: server.head,
      );
      expect(result, isA<PublishCommitSuccess>());
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 1)]);
      expect(server.acceptedBlobs, 3);
    });

    test('a slow request leaves only the rest of the second to wait', () async {
      final server = FakeGitHubGitServer()..beforeBlob = (_) => now += 700;
      await commit(api(server.client), plan(3), head: server.head);
      expect(sleeps, [
        const Duration(milliseconds: 300),
        const Duration(milliseconds: 300),
      ]);
    });

    test('a request slower than the spacing waits not at all', () async {
      final server = FakeGitHubGitServer()..beforeBlob = (_) => now += 1500;
      await commit(api(server.client), plan(3), head: server.head);
      expect(sleeps, isEmpty);
    });

    test(
      'a clock that jumped back never waits longer than the spacing',
      () async {
        final server = FakeGitHubGitServer()
          ..beforeBlob = (n) {
            if (n == 1) now -= 60 * 60 * 1000;
          };
        await commit(api(server.client), plan(2), head: server.head);
        expect(sleeps, [const Duration(seconds: 1)]);
      },
    );

    test('one upload, or none, never waits', () async {
      final server = FakeGitHubGitServer();
      await commit(api(server.client), plan(1), head: server.head);
      await commit(api(server.client), plan(1), head: server.head);
      expect(sleeps, isEmpty);
      expect(server.blobRequests, 2);
    });
  });

  group('stored blobs are reported (J8 a)', () {
    test(
      'each confirmed sha, in order, as soon as GitHub confirms it',
      () async {
        final server = FakeGitHubGitServer();
        final reported = <String>[];
        final requestsAtReport = <int>[];
        await commit(
          api(server.client),
          plan(3),
          head: server.head,
          onBlobStored: (sha) async {
            reported.add(sha);
            requestsAtReport.add(server.blobRequests);
          },
        );
        expect(reported, [sha('cover 1'), sha('cover 2'), sha('cover 3')]);
        expect(requestsAtReport, [1, 2, 3]);
      },
    );

    test('an answer without our sha is not reported, and the commit goes on '
        '(the tree decides)', () async {
      final server = FakeGitHubGitServer();
      var blob = 0;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/git/blobs')) {
          blob++;
          if (blob == 1) {
            return http.Response(jsonEncode({'sha': 'x' * 40}), 201);
          }
          if (blob == 2) return http.Response('created', 201);
        }
        return server.handle(req);
      });
      final reported = <String>[];
      final result = await commit(
        api(client),
        GitHubCommitPlan(
          files: [file('a', 'A'), file('b', 'B'), file('c', 'C')],
          knownBlobShas: const {},
        ),
        head: server.head,
        onBlobStored: (sha) async => reported.add(sha),
      );
      expect(reported, [sha('C')]);
      // The fake never stored A or B, so the tree is refused.
      expect((result as PublishCommitHttpError).code, 422);
    });
  });

  group('rate-limit answers become PublishCommitRateLimited', () {
    test(
      'a secondary-limit 403 partway: how far it got, no tree, no commit',
      () async {
        final server = FakeGitHubGitServer()..acceptBlobs = 2;
        final result = await commit(
          api(server.client),
          plan(4),
          head: server.head,
        );
        final limited = result as PublishCommitRateLimited;
        expect(limited.filesHeld, 2);
        expect(limited.filesToSend, 4);
        expect(limited.wait, isNull);
        expect(limited.refusedNow, isTrue);
        expect(server.blobRequests, 3);
        expect(server.treeRequests, 0);
        expect(server.refMoves, 0);
      },
    );

    test('429 is a rate limit whatever the body says', () async {
      final server = FakeGitHubGitServer()
        ..acceptBlobs = 0
        ..refusal = () => http.Response('', 429);
      final result = await commit(
        api(server.client),
        plan(1),
        head: server.head,
      );
      expect(result, isA<PublishCommitRateLimited>());
    });

    test(
      'retry-after (seconds) is the hint; a huge one is cut to a day',
      () async {
        final server = FakeGitHubGitServer()
          ..acceptBlobs = 0
          ..refusal = () =>
              http.Response('', 403, headers: {'retry-after': '120'});
        var result = await commit(
          api(server.client),
          plan(1),
          head: server.head,
        );
        expect(
          (result as PublishCommitRateLimited).wait,
          const Duration(minutes: 2),
        );
        server.refusal = () =>
            http.Response('', 403, headers: {'retry-after': '9999999999'});
        result = await commit(api(server.client), plan(1), head: server.head);
        expect(
          (result as PublishCommitRateLimited).wait,
          const Duration(days: 1),
        );
      },
    );

    test(
      'no requests left: the hint is the time until x-ratelimit-reset',
      () async {
        const reset = (t0 ~/ 1000) + 300;
        final server = FakeGitHubGitServer()
          ..acceptBlobs = 0
          ..refusal = () => http.Response(
            '{"message":"API rate limit exceeded for user."}',
            403,
            headers: {
              'x-ratelimit-remaining': '0',
              'x-ratelimit-reset': '$reset',
            },
          );
        var result = await commit(
          api(server.client),
          plan(1),
          head: server.head,
        );
        expect(
          (result as PublishCommitRateLimited).wait,
          const Duration(minutes: 5),
        );
        now = t0 + 600 * 1000; // the reset is in the past
        result = await commit(api(server.client), plan(1), head: server.head);
        expect((result as PublishCommitRateLimited).wait, Duration.zero);
      },
    );

    test(
      'a 403 that is not a rate limit stays an HTTP error (permission)',
      () async {
        final server = FakeGitHubGitServer()
          ..acceptBlobs = 0
          ..refusal = () => http.Response(
            '{"message":"Resource not accessible by integration"}',
            403,
          );
        final result = await commit(
          api(server.client),
          plan(1),
          head: server.head,
        );
        expect((result as PublishCommitHttpError).code, 403);
      },
    );

    test(
      'a refused TREE after every blob was sent reports all of them held',
      () async {
        final server = FakeGitHubGitServer();
        final client = MockClient((req) async {
          if (req.url.path.endsWith('/git/trees')) {
            return http.Response(
              '{"message":"You have exceeded a secondary rate limit."}',
              403,
            );
          }
          return server.handle(req);
        });
        final result = await commit(api(client), plan(3), head: server.head);
        final limited = result as PublishCommitRateLimited;
        expect(limited.filesHeld, 3);
        expect(limited.filesToSend, 3);
      },
    );

    for (final step in ['/git/commits', '/git/refs/heads/main']) {
      test('a rate-limited $step step is recognised too', () async {
        final server = FakeGitHubGitServer();
        final client = MockClient((req) async {
          if (req.method != 'GET' && req.url.path.endsWith(step)) {
            return http.Response('', 429);
          }
          return server.handle(req);
        });
        final result = await commit(api(client), plan(1), head: server.head);
        expect(result, isA<PublishCommitRateLimited>());
      });
    }

    test(
      'a primary limit on the first read: nothing sent, nothing held',
      () async {
        final client = MockClient(
          (_) async =>
              http.Response('', 403, headers: {'x-ratelimit-remaining': '0'}),
        );
        final result = await commit(api(client), plan(2), head: 'x');
        final limited = result as PublishCommitRateLimited;
        expect(limited.filesHeld, 0);
        expect(limited.filesToSend, 2);
        expect(limited.wait, isNull);
      },
    );

    test(
      'an oversized error body is not searched (stays an HTTP error)',
      () async {
        final server = FakeGitHubGitServer()
          ..acceptBlobs = 0
          ..refusal = () => http.Response(
            jsonEncode({'message': 'rate limit ${'x' * (70 * 1024)}'}),
            403,
          );
        final result = await commit(
          api(server.client),
          plan(1),
          head: server.head,
        );
        expect(result, isA<PublishCommitHttpError>());
      },
    );
  });

  for (final step in ['/git/trees', '/git/commits']) {
    test('an accepted $step answer without a sha is an HTTP error; the ref '
        'never moves', () async {
      final server = FakeGitHubGitServer();
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path.endsWith(step)) {
          return http.Response('{}', 201);
        }
        return server.handle(req);
      });
      final result = await commit(api(client), plan(1), head: server.head);
      expect((result as PublishCommitHttpError).code, 201);
      expect(server.refMoves, 0);
    });
  }

  test('a tree naming a blob the repository does not hold is a 422 (the '
      'real API answer, plan A.6 #100)', () async {
    final server = FakeGitHubGitServer();
    final result = await commit(
      api(server.client),
      GitHubCommitPlan(
        files: [file('covers/x.jpg', 'never sent')],
        knownBlobShas: {sha('never sent')},
      ),
      head: server.head,
    );
    expect((result as PublishCommitHttpError).code, 422);
    expect(server.blobRequests, 0);
  });
}
