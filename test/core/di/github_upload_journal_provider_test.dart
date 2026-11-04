import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/infrastructure/file_github_upload_journal_store.dart';

import '../../features/publish/support/fake_github_git_server.dart';
import '../../features/publish/support/github_upload_journal_fakes.dart';

/// Plan J8: the one GitHub API provider resumes uploads and keeps GitHub's
/// pause for EVERY commit, and its journal lives in the documents directory.
void main() {
  const t0 = 1_800_000_000_000;

  test('the journal is a file in the app documents directory', () async {
    final dir = Directory.systemTemp.createTempSync('journal_di_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [appDocsDirProvider.overrideWith((ref) async => dir)],
    );
    addTearDown(container.dispose);

    final store = container.read(gitHubUploadJournalStoreProvider);
    expect(store, isA<FileGitHubUploadJournalStore>());
    final journal = GitHubUploadJournal.empty.afterStored('me/lib', [
      'b' * 40,
    ], now: t0);
    expect((await store.write(journal)).isRight(), isTrue);
    expect(File('${dir.path}/github_upload_journal.json').existsSync(), isTrue);
    expect((await store.read()).sameAs(journal), isTrue);
  });

  test("a commit through gitHubApiProvider sends nothing while GitHub's "
      'pause is on', () async {
    final requests = <String>[];
    final store = MemoryGitHubUploadJournalStore(
      GitHubUploadJournal.empty.afterRefusal(now: t0, serverHint: null),
    );
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((req) async {
            requests.add(req.url.path);
            return http.Response('{}', 500);
          }),
        ),
        gitHubUploadJournalStoreProvider.overrideWithValue(store),
        clockProvider.overrideWithValue(() => t0 + 1000),
      ],
    );
    addTearDown(container.dispose);

    final bytes = utf8.encode('{"books":[]}');
    final result = await container
        .read(gitHubApiProvider)
        .commitFiles(
          owner: 'me',
          repo: 'lib',
          branch: 'main',
          token: 'TKN',
          plan: GitHubCommitPlan(
            files: [
              PublishFile(
                path: 'books.json',
                bytes: bytes,
                gitSha: GitBlobSha.of(bytes),
                upload: true,
              ),
            ],
            knownBlobShas: const {},
          ),
          commitMessage: 'm',
          expectedHead: 'a' * 40,
        );

    final limited = result as PublishCommitRateLimited;
    expect(limited.refusedNow, isFalse);
    expect(limited.wait, const Duration(seconds: 59));
    expect(requests, isEmpty);
  });

  test('item 16: the provider is keepAlive, so one pacer serves two commits '
      'even with no listener between them', () async {
    // Before: gitHubApiProvider was autoDispose, so the second read built a
    // NEW HttpGitHubApi with a fresh pacer and the second publish's first
    // blob started immediately after the first publish's last one.
    final server = FakeGitHubGitServer();
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(server.client),
        gitHubUploadJournalStoreProvider.overrideWithValue(
          MemoryGitHubUploadJournalStore(),
        ),
        // `clockProvider` only feeds the upload journal / commit recorder;
        // the adapter paces against its own wall clock, so the second
        // commit's first blob waits a REAL ~1s. That wait is the assertion.
        clockProvider.overrideWithValue(() => t0),
      ],
    );
    addTearDown(container.dispose);

    GitHubCommitPlan oneFile(int n) {
      final bytes = utf8.encode('cover $n');
      return GitHubCommitPlan(
        files: [
          PublishFile(
            path: 'covers/$n.jpg',
            bytes: bytes,
            gitSha: GitBlobSha.of(bytes),
            upload: true,
          ),
        ],
        knownBlobShas: const {},
      );
    }

    Future<PublishCommitResult> commit(int n) => container
        .read(gitHubApiProvider)
        .commitFiles(
          owner: 'me',
          repo: 'lib',
          branch: 'main',
          token: 'TKN',
          plan: oneFile(n),
          commitMessage: 'test $n',
          expectedHead: server.head,
        );

    // Keep the container alive but with no listener on the API: the old
    // autoDispose element would be collected between these two awaits.
    final first = await commit(1);
    expect(first, isA<PublishCommitSuccess>());
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    final sameApi = container.read(gitHubApiProvider);
    expect(identical(sameApi, container.read(gitHubApiProvider)), isTrue);

    final stopwatch = Stopwatch()..start();
    final second = await commit(2);
    stopwatch.stop();
    expect(second, isA<PublishCommitSuccess>());
    expect(server.refMoves, 2, reason: 'one atomic ref move per commit');
    expect(
      stopwatch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 500)),
      reason:
          'the shared pacer waits the remaining second between commits '
          '(a rebuilt API would start immediately)',
    );
  });
}
