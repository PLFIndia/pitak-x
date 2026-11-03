import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/infrastructure/http_github_api.dart';
import 'package:pitaka/features/publish/infrastructure/resumable_upload_github_api.dart';

import '../support/fake_github_git_server.dart';
import '../support/github_upload_journal_fakes.dart';

/// Plan J8 (a): every GitHub commit resumes where a refused attempt stopped,
/// and nothing is sent while GitHub's pause is on. Most tests run the REAL
/// HTTP adapter against an in-memory model of GitHub's Git Data API, so they
/// count the requests GitHub would really see.
void main() {
  const t0 = 1_800_000_000_000;
  const minute = 60 * 1000;
  const repo = 'me/lib';

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

  /// A first publish: `books.json` plus [covers] new covers.
  GitHubCommitPlan firstPublish(int covers) => GitHubCommitPlan(
    files: [
      file('books.json', 'books'),
      for (var n = 1; n <= covers; n++) file('covers/$n.jpg', 'cover $n'),
    ],
    knownBlobShas: const {},
  );

  late int now;
  late FakeGitHubGitServer server;
  late MemoryGitHubUploadJournalStore store;
  late ResumableUploadGitHubApi github;

  ResumableUploadGitHubApi over(http.Client client) => ResumableUploadGitHubApi(
    inner: HttpGitHubApi(
      client: client,
      apiBase: Uri.parse('https://api.github.test'),
      clock: () => now,
      sleep: (d) async => now += d.inMilliseconds,
    ),
    journal: store,
    clock: () => now,
  );

  setUp(() {
    now = t0;
    server = FakeGitHubGitServer(files: {'README.md': utf8.encode('readme')});
    store = MemoryGitHubUploadJournalStore();
    github = over(server.client);
  });

  Future<PublishCommitResult> commit(
    GitHubCommitPlan plan, {
    String owner = 'me',
    String repoName = 'lib',
    ResumableUploadGitHubApi? api,
    Future<void> Function(String)? onBlobStored,
  }) => (api ?? github).commitFiles(
    owner: owner,
    repo: repoName,
    branch: 'main',
    token: 'TKN',
    plan: plan,
    commitMessage: 'test',
    expectedHead: server.head,
    onBlobStored: onBlobStored,
  );

  group('a large first publish finishes across attempts', () {
    test('refused partway, paused, resumed twice, then ONE commit; no blob '
        'is ever sent twice', () async {
      final plan = firstPublish(9); // 10 files to send
      final reported = <String>[];

      // Attempt 1: GitHub accepts 4 blobs, then its limit refuses.
      server.acceptBlobs = 4;
      final first = await commit(
        plan,
        onBlobStored: (s) async => reported.add(s),
      );
      final limited = first as PublishCommitRateLimited;
      expect(limited.filesHeld, 4);
      expect(limited.filesToSend, 10);
      expect(limited.refusedNow, isTrue);
      expect(limited.wait, const Duration(minutes: 1));
      expect(server.blobRequests, 5);
      expect(server.treeRequests, 0);
      expect(store.saved.heldFor(repo, now: now), hasLength(4));
      expect(reported, hasLength(4)); // the caller's own callback still runs

      // Attempt 2, 30 s later: the pause is on, so NOTHING reaches GitHub.
      now += 30 * 1000;
      final requestsBefore = server.log.length;
      final paused = await commit(plan) as PublishCommitRateLimited;
      expect(server.log.length, requestsBefore);
      expect(paused.refusedNow, isFalse);
      expect(paused.filesHeld, 4);
      expect(paused.filesToSend, 10);
      expect(paused.wait, const Duration(seconds: 30));

      // Attempt 3, after the pause: the 4 held blobs are named, not sent;
      // GitHub takes 3 more and refuses again.
      now += minute;
      server
        ..acceptBlobs = 3
        ..blobRequests = 0;
      final third = await commit(plan) as PublishCommitRateLimited;
      expect(server.blobRequests, 4); // 3 accepted + the refused one
      expect(third.filesHeld, 7);
      expect(third.filesToSend, 10);
      // Progress was made, so the backoff starts again at one minute.
      expect(third.wait, const Duration(minutes: 1));

      // Attempt 4: the limit has lifted; only the last 3 are sent.
      now += 2 * minute;
      server
        ..acceptBlobs = null
        ..blobRequests = 0;
      final last = await commit(plan);
      expect(last, isA<PublishCommitSuccess>());
      expect(server.blobRequests, 3);
      expect((last as PublishCommitSuccess).uploadedPaths, hasLength(3));
      expect(server.refMoves, 1);
      expect(server.headFiles.keys, containsAll(plan.files.map((f) => f.path)));
      for (final f in plan.files) {
        expect(server.headFiles[f.path], f.gitSha);
      }
      // Done: nothing left to remember, no pause.
      expect(store.saved.sameAs(GitHubUploadJournal.empty), isTrue);
      // 4 + 3 + 3 accepted: every file sent exactly once.
      expect(server.acceptedBlobs, 10);
    });

    test('blobs held for one repository are never named in another', () async {
      store = MemoryGitHubUploadJournalStore(
        GitHubUploadJournal.empty.afterStored('me/other', [
          sha('cover 1'),
        ], now: t0),
      );
      github = over(server.client);
      final result = await commit(firstPublish(1));
      expect(result, isA<PublishCommitSuccess>());
      expect(server.blobRequests, 2);
    });

    test(
      'the repository key ignores case (GitHub names are case-insensitive)',
      () async {
        // The fake server only knows me/lib, so seed what an attempt to it
        // left, and commit as Me/Lib through a client that lower-cases.
        server.objects.add(sha('cover 1'));
        store = MemoryGitHubUploadJournalStore(
          GitHubUploadJournal.empty.afterStored(repo, [
            sha('cover 1'),
          ], now: t0),
        );
        final api = over(_LowerCasingClient(server));
        final result = await commit(
          firstPublish(1),
          owner: 'Me',
          repoName: 'Lib',
          api: api,
        );
        expect(result, isA<PublishCommitSuccess>());
        expect(server.blobRequests, 1); // only books.json
      },
    );

    test('entries older than a week are sent again', () async {
      server.objects.add(sha('cover 1'));
      store = MemoryGitHubUploadJournalStore(
        GitHubUploadJournal.empty.afterStored(repo, [
          sha('cover 1'),
        ], now: t0 - 8 * 24 * 60 * minute),
      );
      github = over(server.client);
      await commit(firstPublish(1));
      expect(server.blobRequests, 2);
    });
  });

  group('progress survives an interruption', () {
    test('saved every 20 blobs while uploading, and again when the connection '
        'drops', () async {
      server.beforeBlob = (n) {
        if (n == 26) throw http.ClientException('connection reset');
      };
      await expectLater(
        commit(firstPublish(40)),
        throwsA(isA<GitHubApiException>()),
      );
      // One save at 20 blobs (an app closed then keeps those), the final
      // flush at 25.
      expect(store.writes.map((j) => j.heldFor(repo, now: now).length), [
        20,
        25,
      ]);

      // The next attempt sends only the 16 not yet held.
      server
        ..beforeBlob = null
        ..blobRequests = 0;
      final result = await commit(firstPublish(40));
      expect(result, isA<PublishCommitSuccess>());
      expect(server.blobRequests, 16);
    });
  });

  group('a remembered blob GitHub no longer holds', () {
    test('the 422 forgets the blobs the tree named, keeps the new ones, and '
        'the next attempt sends them again', () async {
      // The journal says GitHub holds cover 1, but the repository does not.
      store = MemoryGitHubUploadJournalStore(
        GitHubUploadJournal.empty.afterStored(repo, [sha('cover 1')], now: t0),
      );
      github = over(server.client);
      final plan = firstPublish(1);

      final refused = await commit(plan);
      expect((refused as PublishCommitHttpError).code, 422);
      expect(store.saved.heldFor(repo, now: now), {sha('books')});

      server.blobRequests = 0;
      final retried = await commit(plan);
      expect(retried, isA<PublishCommitSuccess>());
      expect(server.blobRequests, 1); // cover 1 sent; books.json named
    });

    test('a 422 when nothing remembered was named forgets nothing', () async {
      final inner = _ScriptedInner((plan, onStored) async {
        await onStored?.call(sha('books'));
        return const PublishCommitHttpError(422, 'x');
      });
      store = MemoryGitHubUploadJournalStore(
        GitHubUploadJournal.empty.afterStored(repo, [
          sha('elsewhere'),
        ], now: t0),
      );
      final api = ResumableUploadGitHubApi(
        inner: inner,
        journal: store,
        clock: () => now,
      );
      await commit(firstPublish(0), api: api);
      expect(store.saved.heldFor(repo, now: now), {
        sha('elsewhere'),
        sha('books'),
      });
    });
  });

  group('bookkeeping', () {
    ResumableUploadGitHubApi scripted(
      Future<PublishCommitResult> Function(
        GitHubCommitPlan plan,
        Future<void> Function(String)? onStored,
      )
      answer,
    ) => ResumableUploadGitHubApi(
      inner: _ScriptedInner(answer),
      journal: store,
      clock: () => now,
    );

    test(
      'an ordinary publish with nothing remembered writes no journal',
      () async {
        final result = await commit(firstPublish(1));
        expect(result, isA<PublishCommitSuccess>());
        expect(store.writes, isEmpty);
      },
    );

    test(
      'a landed commit ends an expired pause and the refusal count',
      () async {
        store = MemoryGitHubUploadJournalStore(
          GitHubUploadJournal.empty
              .afterRefusal(now: t0, serverHint: null)
              .afterRefusal(now: t0, serverHint: null),
        );
        github = over(server.client);
        now += 10 * minute;
        await commit(firstPublish(0));
        expect(store.saved.refusals, 0);
        expect(store.saved.pausedUntil, isNull);
      },
    );

    test('a stale head sends nothing and writes nothing', () async {
      final api = scripted((_, _) async => const PublishCommitStale());
      expect(
        await commit(firstPublish(1), api: api),
        isA<PublishCommitStale>(),
      );
      expect(store.writes, isEmpty);
    });

    test(
      'the server hint sets the pause; the result reports the pause kept',
      () async {
        final api = scripted(
          (plan, onStored) async => const PublishCommitRateLimited(
            filesHeld: 0,
            filesToSend: 2,
            wait: Duration(minutes: 7),
            refusedNow: true,
          ),
        );
        final result = await commit(firstPublish(1), api: api);
        expect(
          (result as PublishCommitRateLimited).wait,
          const Duration(minutes: 7),
        );
        expect(store.saved.pauseLeft(now), const Duration(minutes: 7));
        expect(store.saved.refusals, 1);
      },
    );

    test(
      'a journal that cannot be saved never changes the commit result',
      () async {
        store.failWrites = true;
        server.acceptBlobs = 1;
        final result =
            await commit(firstPublish(2)) as PublishCommitRateLimited;
        expect(result.filesHeld, 1);
        expect(result.filesToSend, 3);
        expect(result.wait, const Duration(minutes: 1));
      },
    );

    test('a repository name the journal cannot store is forwarded untouched '
        'and never journaled', () async {
      GitHubCommitPlan? seen;
      final api = scripted((plan, _) async {
        seen = plan;
        return const PublishCommitSuccess('c', []);
      });
      final plan = firstPublish(1);
      await commit(plan, owner: 'evil.example', api: api);
      expect(identical(seen, plan), isTrue);
      expect(store.reads, 0);
      expect(store.writes, isEmpty);
    });
  });

  test('every other call is forwarded unchanged', () async {
    final inner = _ScriptedInner((_, _) async => const PublishCommitStale());
    final api = ResumableUploadGitHubApi(
      inner: inner,
      journal: store,
      clock: () => now,
    );
    expect(await api.currentUserLogin('t'), 'login');
    expect((await api.userRepos('t')).repos, isEmpty);
    expect(await api.repository(owner: 'o', repo: 'r', token: 't'), isNull);
    expect(await api.pagesSite(owner: 'o', repo: 'r', token: 't'), isNull);
    expect(
      await api.createUserRepo(name: 'r', token: 't'),
      isA<RepoAlreadyExists>(),
    );
    await api.enablePages(owner: 'o', repo: 'r', branch: 'main', token: 't');
    expect(
      await api.branchHead(owner: 'o', repo: 'r', branch: 'main', token: 't'),
      'head',
    );
    expect(
      (await api.treeAt(
        owner: 'o',
        repo: 'r',
        branch: 'main',
        headSha: 'head',
        token: 't',
      )).headSha,
      'head',
    );
    expect(
      await api.requestDeviceCode(clientId: 'c', scope: 's'),
      isA<DeviceCodeGrant>(),
    );
    expect(
      await api.pollAccessToken(clientId: 'c', deviceCode: 'd'),
      isA<PollPending>(),
    );
    expect(inner.calls, [
      'currentUserLogin',
      'userRepos',
      'repository',
      'pagesSite',
      'createUserRepo',
      'enablePages',
      'branchHead',
      'treeAt',
      'requestDeviceCode',
      'pollAccessToken',
    ]);
  });
}

/// Sends every request to [server] with its path lower-cased, as GitHub
/// itself treats owner and repository names.
final class _LowerCasingClient extends http.BaseClient {
  _LowerCasingClient(this.server);

  final FakeGitHubGitServer server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final original = request as http.Request;
    final copy = http.Request(
      original.method,
      original.url.replace(path: original.url.path.toLowerCase()),
    )..headers.addAll(original.headers);
    if (original.method != 'GET') copy.body = original.body;
    final response = await server.handle(copy);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

/// A [GitHubApi] whose commit answers through [answer]; every other call
/// records its name and returns a fixed value.
final class _ScriptedInner implements GitHubApi {
  _ScriptedInner(this.answer);

  final Future<PublishCommitResult> Function(
    GitHubCommitPlan plan,
    Future<void> Function(String)? onStored,
  )
  answer;

  final List<String> calls = [];

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
  }) => answer(plan, onBlobStored);

  @override
  Future<String> currentUserLogin(String token) async {
    calls.add('currentUserLogin');
    return 'login';
  }

  @override
  Future<RepoListing> userRepos(String token) async {
    calls.add('userRepos');
    return const RepoListing(repos: [], truncated: false);
  }

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) async {
    calls.add('repository');
    return null;
  }

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async {
    calls.add('pagesSite');
    return null;
  }

  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) async {
    calls.add('createUserRepo');
    return const RepoAlreadyExists();
  }

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async => calls.add('enablePages');

  @override
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    calls.add('branchHead');
    return 'head';
  }

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) async {
    calls.add('treeAt');
    return const GitHubTreeSnapshot(
      repo: 'o/r',
      branch: 'main',
      headSha: 'head',
      files: {},
      truncated: false,
    );
  }

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async {
    calls.add('requestDeviceCode');
    return const DeviceCodeGrant(
      deviceCode: 'd',
      userCode: 'u',
      verificationUri: 'https://github.com/login/device',
      expiresInSeconds: 900,
      intervalSeconds: 5,
    );
  }

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    calls.add('pollAccessToken');
    return const PollPending();
  }
}
