import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';

/// CV5 (ADR 0020 Decision 6): the one rule for which bytes a GitHub commit
/// sends. The use-case suites prove each caller uses it; this pins the rule.
void main() {
  PublishFile built(String path, String content, {bool upload = true}) {
    final bytes = utf8.encode(content);
    return PublishFile(
      path: path,
      bytes: upload ? bytes : const [],
      gitSha: GitBlobSha.of(bytes),
      upload: upload,
    );
  }

  String sha(String content) => GitBlobSha.of(utf8.encode(content));

  test('with nothing known, every changed file is sent (the behaviour before '
      'ADR 0020)', () {
    final plan = GitHubCommitPlan(
      files: [built('books.json', 'a'), built('covers/1.jpg', 'b')],
      knownBlobShas: const {},
    );
    expect(plan.files.map((f) => f.upload), [true, true]);
    expect(plan.uploadedPaths, ['books.json', 'covers/1.jpg']);
    expect(plan.hasUploads, isTrue);
    expect(plan.uploadBytes, 2);
  });

  test('a file marked unchanged is never sent, even when nothing is known '
      'about it (it may carry no bytes)', () {
    final plan = GitHubCommitPlan(
      files: [built('covers/1.jpg', 'b', upload: false)],
      knownBlobShas: const {},
    );
    final entry = plan.files.single;
    expect(entry.upload, isFalse);
    expect(entry.bytes, isEmpty);
    expect(entry.gitSha, sha('b'));
    expect(plan.hasUploads, isFalse);
    expect(plan.uploadedPaths, isEmpty);
    expect(plan.uploadBytes, 0);
  });

  test('a changed file whose bytes the branch already holds at ANY path is '
      'named by its sha, not sent', () {
    final plan = GitHubCommitPlan(
      files: [
        built('covers/new-name.jpg', 'picture'),
        built('books.json', 'x'),
      ],
      knownBlobShas: {sha('picture'), 'some-other-sha'},
    );
    final cover = plan.files.first;
    expect(cover.path, 'covers/new-name.jpg');
    expect(cover.gitSha, sha('picture'));
    expect(cover.upload, isFalse);
    expect(plan.uploadedPaths, ['books.json']);
    expect(plan.uploadBytes, 1);
  });

  test('two files with the same bytes in one commit are sent once: the first '
      'carries the upload, the second names it', () {
    final plan = GitHubCommitPlan(
      files: [
        built('index.html', 'moved'),
        built('404.html', 'moved'),
        built('covers/2.jpg', 'other'),
      ],
      knownBlobShas: const {},
    );
    expect(plan.files.map((f) => f.upload), [true, false, true]);
    expect(plan.files.map((f) => f.gitSha).take(2).toSet(), {sha('moved')});
    expect(plan.uploadedPaths, ['index.html', 'covers/2.jpg']);
  });

  test('an unchanged file does not stop a changed duplicate from being sent '
      '(only a SENT or KNOWN blob counts as held)', () {
    final plan = GitHubCommitPlan(
      files: [
        built('covers/old.jpg', 'same', upload: false),
        built('covers/new.jpg', 'same'),
      ],
      knownBlobShas: const {},
    );
    expect(plan.files.map((f) => f.upload), [false, true]);
  });

  test('a duplicate of a known blob is sent by neither file', () {
    final plan = GitHubCommitPlan(
      files: [built('a.jpg', 'same'), built('b.jpg', 'same')],
      knownBlobShas: {sha('same')},
    );
    expect(plan.hasUploads, isFalse);
    expect(plan.files.map((f) => f.path), ['a.jpg', 'b.jpg']);
  });

  test('the tree keeps every file in order, with its path, sha and bytes, '
      'and cannot be changed afterwards', () {
    final files = [
      built('books.json', 'b'),
      built('index.html', 'i', upload: false),
      built('covers/1.jpg', 'c'),
    ];
    final plan = GitHubCommitPlan(files: files, knownBlobShas: {sha('c')});
    expect(plan.files.map((f) => f.path), [
      'books.json',
      'index.html',
      'covers/1.jpg',
    ]);
    expect(plan.files.map((f) => f.gitSha), files.map((f) => f.gitSha));
    expect(plan.files.first.bytes, utf8.encode('b'));
    expect(
      () => plan.files.add(
        const DesiredFile(path: 'x', bytes: [], gitSha: 'x', upload: true),
      ),
      throwsUnsupportedError,
    );
  });

  test('an empty commit (deletions only) sends nothing', () {
    final plan = GitHubCommitPlan(files: const [], knownBlobShas: const {});
    expect(plan.files, isEmpty);
    expect(plan.hasUploads, isFalse);
    expect(plan.uploadBytes, 0);
  });

  group('GitHubTreeSnapshot.blobShas', () {
    test('holds every blob sha of the tree, owned or not, once', () {
      const tree = GitHubTreeSnapshot(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'HEAD',
        files: {
          'README.md': 'r',
          'covers/1.jpg': 'c',
          'old/copy.jpg': 'c',
          'books.json': 'b',
        },
        truncated: false,
      );
      expect(tree.blobShas, {'r', 'c', 'b'});
    });
  });
}
