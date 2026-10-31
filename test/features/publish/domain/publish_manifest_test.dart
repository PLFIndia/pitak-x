import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// A tree with the given blobs at [head].
GitHubTreeSnapshot tree(
  Map<String, String> files, {
  String head = 'head-a',
  String branch = 'main',
  String repo = 'me/lib',
  bool truncated = false,
}) => GitHubTreeSnapshot(
  repo: repo,
  branch: branch,
  headSha: head,
  files: files,
  truncated: truncated,
);

void main() {
  group('schema 2 encoding', () {
    test('round-trips every field through JSON', () {
      const manifest = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'abc',
        ownershipConfirmed: true,
        state: PublishState.live,
        fileShas: {'books.json': 'sha-1'},
        coverUrlByBookId: {'1': 'https://covers.example/1.jpg'},
      );
      final decoded = PublishManifest.fromJson(manifest.toJson());
      expect(decoded.schema, PublishManifest.currentSchema);
      expect(decoded.repo, 'me/lib');
      expect(decoded.branch, 'main');
      expect(decoded.headSha, 'abc');
      expect(decoded.ownershipConfirmed, isTrue);
      expect(decoded.state, PublishState.live);
      expect(decoded.fileShas, {'books.json': 'sha-1'});
      expect(decoded.coverUrlByBookId, {'1': 'https://covers.example/1.jpg'});
    });

    test('writes no token-shaped or account field', () {
      const manifest = PublishManifest(repo: 'me/lib', branch: 'main');
      final json = manifest.toJson();
      expect(json['schema'], 2);
      expect(
        json.keys,
        everyElement(
          isNot(
            anyOf(
              contains('token'),
              contains('secret'),
              contains('credential'),
            ),
          ),
        ),
      );
    });

    test('an unknown state is read as deployed, never as live', () {
      final decoded = PublishManifest.fromJson({
        'schema': 2,
        'repo': 'me/lib',
        'branch': 'main',
        'state': 'something-new',
        'fileShas': <String, String>{},
      });
      expect(decoded.state, PublishState.deployed);
    });
  });

  group('schema 1 (legacy) records', () {
    test('decode as deployed, with ownership derived from the paths', () {
      final decoded = PublishManifest.fromJson({
        'repo': 'me/lib',
        'fileShas': {'books.json': 'sha-1', 'index.html': 'sha-2'},
        'coverUrlByBookId': <String, String>{},
      });
      expect(decoded.schema, 1);
      expect(decoded.isLegacy, isTrue);
      // The old app never stored a read-back result: claiming "live" would be
      // an invented fact (R5).
      expect(decoded.state, PublishState.deployed);
      // Those paths were written by this app, so they are app-owned by
      // construction (R13).
      expect(decoded.ownershipConfirmed, isTrue);
      expect(decoded.headSha, isNull);
      expect(decoded.branch, isNull);
    });

    test('an empty legacy record claims no ownership', () {
      final decoded = PublishManifest.fromJson({'repo': 'me/lib'});
      expect(decoded.ownershipConfirmed, isFalse);
      expect(decoded.fileShas, isEmpty);
    });

    test('odd shapes degrade to empty maps instead of throwing', () {
      final decoded = PublishManifest.fromJson({
        'repo': 7,
        'fileShas': 'nope',
        'coverUrlByBookId': [1, 2],
      });
      expect(decoded.repo, isNull);
      expect(decoded.fileShas, isEmpty);
      expect(decoded.coverUrlByBookId, isEmpty);
    });
  });

  group('reconciledFrom (R6)', () {
    const local = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'head-a',
      ownershipConfirmed: true,
      fileShas: {'books.json': 'local-books', 'covers/1.jpg': 'local-cover'},
      coverUrlByBookId: {'1': 'https://covers.example/1.jpg'},
    );

    test('takes every sha from the tree, not from the local record', () {
      final reconciled = local.reconciledFrom(
        tree: tree({
          'books.json': 'remote-books',
          'covers/1.jpg': 'local-cover',
        }),
        ownerRepo: 'me/lib',
        branch: 'main',
      );
      expect(reconciled.shaFor('books.json'), 'remote-books');
      expect(reconciled.shaFor('covers/1.jpg'), 'local-cover');
      expect(reconciled.headSha, 'head-a');
    });

    test('drops a claimed path that the tree no longer has', () {
      final reconciled = local.reconciledFrom(
        tree: tree({'books.json': 'remote-books'}),
        ownerRepo: 'me/lib',
        branch: 'main',
      );
      expect(reconciled.shaFor('covers/1.jpg'), isNull);
      expect(reconciled.ownedPaths, ['books.json']);
    });

    test('never adopts a file the record does not claim', () {
      final reconciled = local.reconciledFrom(
        tree: tree({
          'books.json': 'remote-books',
          'README.md': 'human-file',
          'notes/private.txt': 'human-note',
        }),
        ownerRepo: 'me/lib',
        branch: 'main',
      );
      expect(reconciled.shaFor('README.md'), isNull);
      expect(reconciled.shaFor('notes/private.txt'), isNull);
      // Kept cover-source metadata survives: it describes the library's
      // covers, not the site.
      expect(reconciled.coverSourceFor('1'), 'https://covers.example/1.jpg');
    });

    test('a different repo claims nothing (a full rebuild)', () {
      final reconciled = local.reconciledFrom(
        tree: tree({'books.json': 'remote-books'}, repo: 'me/other'),
        ownerRepo: 'me/other',
        branch: 'main',
      );
      expect(reconciled.ownedPaths, isEmpty);
      expect(reconciled.ownershipConfirmed, isFalse);
      expect(reconciled.repo, 'me/other');
    });

    test('a re-pointed Pages branch claims nothing', () {
      final reconciled = local.reconciledFrom(
        tree: tree({'books.json': 'remote-books'}, branch: 'gh-pages'),
        ownerRepo: 'me/lib',
        branch: 'gh-pages',
      );
      expect(reconciled.ownedPaths, isEmpty);
      expect(reconciled.branch, 'gh-pages');
    });

    test('live survives only while it describes the read head', () {
      final live = local.asLive();
      expect(
        live
            .reconciledFrom(
              tree: tree({'books.json': 'b', 'covers/1.jpg': 'c'}),
              ownerRepo: 'me/lib',
              branch: 'main',
            )
            .state,
        PublishState.live,
      );
      expect(
        live
            .reconciledFrom(
              tree: tree({
                'books.json': 'b',
                'covers/1.jpg': 'c',
              }, head: 'head-b'),
              ownerRepo: 'me/lib',
              branch: 'main',
            )
            .state,
        PublishState.deployed,
      );
    });
  });

  group('state transitions', () {
    test('afterCommit records the head, the merged set and ownership', () {
      const local = PublishManifest(repo: 'me/lib', branch: 'main');
      final committed = local.afterCommit(
        commitSha: 'new-head',
        mergedShas: {'books.json': 'sha'},
        coverUrlByBookId: {'1': 'src'},
      );
      expect(committed.headSha, 'new-head');
      expect(committed.state, PublishState.deployed);
      expect(committed.ownershipConfirmed, isTrue);
      expect(committed.fileShas, {'books.json': 'sha'});
      expect(committed.coverSourceFor('1'), 'src');
    });

    test('asLive keeps everything and changes only the state', () {
      const committed = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'new-head',
        ownershipConfirmed: true,
        fileShas: {'books.json': 'sha'},
      );
      final live = committed.asLive();
      expect(live.state, PublishState.live);
      expect(live.headSha, 'new-head');
      expect(live.fileShas, committed.fileShas);
    });

    test('describes() requires both repo and branch', () {
      const manifest = PublishManifest(repo: 'me/lib', branch: 'main');
      expect(manifest.describes(ownerRepo: 'me/lib', branch: 'main'), isTrue);
      expect(
        manifest.describes(ownerRepo: 'me/lib', branch: 'gh-pages'),
        isFalse,
      );
      expect(manifest.describes(ownerRepo: 'me/x', branch: 'main'), isFalse);
      expect(
        PublishManifest.empty.describes(ownerRepo: 'me/lib', branch: 'main'),
        isFalse,
      );
    });
  });
}
