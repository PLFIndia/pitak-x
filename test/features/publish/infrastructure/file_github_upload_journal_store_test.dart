import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/features/publish/domain/github_upload_journal.dart';
import 'package:pitaka/features/publish/infrastructure/file_github_upload_journal_store.dart';

/// Plan J8 (a): the journal file. Every read problem is "nothing
/// remembered" (the safe direction: more uploads); a save is atomic and its
/// failure is reported.
void main() {
  const t0 = 1_800_000_000_000;
  final sha = 'a' * 40;
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('journal_store_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  FileGitHubUploadJournalStore store([String? path]) =>
      FileGitHubUploadJournalStore(directory: () async => path ?? dir.path);

  File journalFile() => File(p.join(dir.path, 'github_upload_journal.json'));

  test('nothing stored reads as empty', () async {
    final read = await store().read();
    expect(read.sameAs(GitHubUploadJournal.empty), isTrue);
  });

  test('a saved journal reads back the same, with no temp file left', () async {
    final journal = GitHubUploadJournal.empty
        .afterStored('me/lib', [sha], now: t0)
        .afterRefusal(now: t0, serverHint: null);
    expect((await store().write(journal)).isRight(), isTrue);
    final read = await store().read();
    expect(read.sameAs(journal), isTrue);
    expect(dir.listSync().map((e) => p.basename(e.path)), [
      'github_upload_journal.json',
    ]);
    // Public data only: the file holds the repository, the sha and times.
    expect(journalFile().readAsStringSync(), contains('me/lib'));
  });

  test('a save creates the directory when it is missing', () async {
    final nested = p.join(dir.path, 'a', 'b');
    final journal = GitHubUploadJournal.empty.afterStored('me/lib', [
      sha,
    ], now: t0);
    expect((await store(nested).write(journal)).isRight(), isTrue);
    expect((await store(nested).read()).blobCount, 1);
  });

  for (final damaged in <String, String>{
    'malformed JSON': '{"version": 1,',
    'another shape': jsonEncode({'hello': 'world'}),
    'a newer version': jsonEncode({
      'version': 2,
      'pausedUntil': null,
      'refusals': 0,
      'repos': <String, Object>{},
    }),
  }.entries) {
    test('${damaged.key} reads as empty', () async {
      journalFile().writeAsStringSync(damaged.value);
      expect((await store().read()).sameAs(GitHubUploadJournal.empty), isTrue);
    });
  }

  test('a file over the size cap is not even parsed', () async {
    journalFile().writeAsStringSync(
      ' ' * (FileGitHubUploadJournalStore.maxFileBytes + 1),
    );
    expect((await store().read()).sameAs(GitHubUploadJournal.empty), isTrue);
  });

  test('a directory that cannot be resolved reads as empty and fails the '
      'save as a value, never a throw', () async {
    final broken = FileGitHubUploadJournalStore(
      directory: () async => throw const FileSystemException('no dir'),
    );
    expect((await broken.read()).sameAs(GitHubUploadJournal.empty), isTrue);
    expect((await broken.write(GitHubUploadJournal.empty)).isLeft(), isTrue);
  });

  test('a save that cannot write is a typed failure', () async {
    // A plain FILE where the directory should be.
    final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('x');
    final result = await store(blocker.path).write(GitHubUploadJournal.empty);
    expect(result.isLeft(), isTrue);
  });
}
