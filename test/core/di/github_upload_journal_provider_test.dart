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
}
