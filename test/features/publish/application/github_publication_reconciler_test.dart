import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

class _Api implements GitHubGitDataApi {
  _Api({
    this.snapshot,
    this.throwOnTree = false,
    this.throwOnHead = false,
    String? head,
  }) : head = head ?? snapshot?.headSha ?? 'head-a';

  /// What `treeAt` answers.
  final GitHubTreeSnapshot? snapshot;

  /// What `branchHead` answers (the snapshot's head unless a test says).
  final String head;
  final bool throwOnTree;
  final bool throwOnHead;
  int headReads = 0;
  int treeReads = 0;
  String? readBranch;

  /// The commit `treeAt` was asked for.
  String? treeAskedFor;

  @override
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    headReads++;
    readBranch = branch;
    if (throwOnHead) throw const GitHubApiException('boom');
    return head;
  }

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) async {
    treeReads++;
    treeAskedFor = headSha;
    if (throwOnTree) throw const GitHubApiException('boom');
    return snapshot!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected GitHub operation: $invocation');
}

GitHubTreeSnapshot snapshot({
  Map<String, String> files = const {'books.json': 'sha-books'},
  String head = 'head-a',
  String branch = 'main',
  bool truncated = false,
}) => GitHubTreeSnapshot(
  repo: 'me/lib',
  branch: branch,
  headSha: head,
  files: files,
  truncated: truncated,
);

void main() {
  final target = GitHubPublishTarget.create('me/lib')!;

  test('returns the reconciled record and the head it read', () async {
    final api = _Api(
      snapshot: snapshot(
        files: {'books.json': 'sha-books', 'covers/1.jpg': 'sha-cover'},
      ),
    );
    final result = await GitHubPublicationReconciler(api).call(
      target: target,
      branch: 'main',
      token: 'TKN',
      local: const PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        fileShas: {'books.json': 'stale', 'covers/1.jpg': 'sha-cover'},
      ),
    );

    final publication = result.toNullable()!;
    expect(publication.headSha, 'head-a');
    expect(publication.manifest.shaFor('books.json'), 'sha-books');
    expect(api.readBranch, 'main');
  });

  test('knows every blob the branch holds, also at paths it does not own '
      '(CV5), while the record still claims none of them', () async {
    final api = _Api(
      snapshot: snapshot(
        files: {
          'books.json': 'sha-books',
          'README.md': 'sha-readme',
          'old/cover.jpg': 'sha-old-cover',
        },
      ),
    );
    final result = await GitHubPublicationReconciler(api).call(
      target: target,
      branch: 'main',
      token: 'TKN',
      local: const PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        fileShas: {'books.json': 'sha-books'},
      ),
    );

    final publication = result.toNullable()!;
    expect(publication.knownBlobShas, {
      'sha-books',
      'sha-readme',
      'sha-old-cover',
    });
    expect(publication.manifest.ownedPaths, ['books.json']);
  });

  test('an unreadable tree is a typed failure with a fixed message', () async {
    final result = await GitHubPublicationReconciler(_Api(throwOnTree: true))
        .call(
          target: target,
          branch: 'main',
          token: 'TKN',
          local: PublishManifest.empty,
        );

    expect(result.isLeft(), isTrue);
    expect(
      (result.swap().toNullable()! as ValidationFailure).message,
      gitHubSiteStateUnreadableMessage,
    );
  });

  test(
    'a truncated tree refuses with the repository-too-large message',
    () async {
      final result =
          await GitHubPublicationReconciler(
            _Api(snapshot: snapshot(truncated: true)),
          ).call(
            target: target,
            branch: 'main',
            token: 'TKN',
            local: PublishManifest.empty,
          );

      expect(result.isLeft(), isTrue);
      expect(
        (result.swap().toNullable()! as ValidationFailure).message,
        gitHubTreeTooLargeMessage,
      );
    },
  );

  test('an unreadable head is a typed failure; no tree is read', () async {
    final api = _Api(throwOnHead: true);
    final result = await GitHubPublicationReconciler(api).call(
      target: target,
      branch: 'main',
      token: 'TKN',
      local: PublishManifest.empty,
    );

    expect(
      (result.swap().toNullable()! as ValidationFailure).message,
      gitHubSiteStateUnreadableMessage,
    );
    expect(api.treeReads, 0);
  });

  test('the tree is read at the head that was just read', () async {
    final api = _Api(
      snapshot: snapshot(head: 'head-b'),
      head: 'head-b',
    );
    final result = await GitHubPublicationReconciler(api).call(
      target: target,
      branch: 'main',
      token: 'TKN',
      local: PublishManifest.empty,
    );

    expect(api.treeAskedFor, 'head-b');
    expect(result.toNullable()!.treeRead, isTrue);
  });

  group('plan SP4: an unchanged head skips the tree read', () {
    // The record this phone keeps after a proven publish at `head-a`.
    const liveRecord = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'head-a',
      ownershipConfirmed: true,
      state: PublishState.live,
      fileShas: {'books.json': 'sha-books', 'covers/1.jpg': 'sha-cover'},
      coverUrlByBookId: {'1': 'covers/a.jpg'},
      proofPath: PublishProofPath.booksJson,
      catalogueKeyed: true,
      coverRendition: 1,
      committedAt: 1700000000000,
    );

    Future<(ReconciledPublication, _Api)> reconcile(
      PublishManifest local, {
      String head = 'head-a',
      String branch = 'main',
    }) async {
      final api = _Api(
        head: head,
        snapshot: snapshot(
          head: head,
          branch: branch,
          files: {
            'books.json': 'sha-books',
            'covers/1.jpg': 'sha-cover',
            'README.md': 'sha-readme',
          },
        ),
      );
      final result = await GitHubPublicationReconciler(
        api,
      ).call(target: target, branch: branch, token: 'TKN', local: local);
      return (result.toNullable()!, api);
    }

    test('a live record of this repo and branch at this head: one head '
        'read, no tree read, the record as published', () async {
      final (publication, api) = await reconcile(liveRecord);

      expect(api.headReads, 1);
      expect(api.treeReads, 0, reason: 'plan G.5: no tree request');
      expect(publication.treeRead, isFalse);
      expect(publication.headSha, 'head-a');
      expect(publication.manifest.state, PublishState.live);
      expect(publication.manifest.catalogueKeyed, isTrue);
      expect(publication.manifest.coverRendition, 1);
      expect(publication.manifest.proofPath, PublishProofPath.booksJson);
      expect(publication.manifest.committedAt, 1700000000000);
      expect(publication.manifest.ownedPaths, ['books.json', 'covers/1.jpg']);
      // CV5: the recorded shas, which the head tree holds by construction.
      expect(publication.knownBlobShas, {'sha-books', 'sha-cover'});
    });

    test('a moved head reads the whole tree at the new head', () async {
      final (publication, api) = await reconcile(liveRecord, head: 'head-b');

      expect(api.treeReads, 1);
      expect(api.treeAskedFor, 'head-b');
      expect(publication.treeRead, isTrue);
      expect(publication.manifest.state, PublishState.deployed);
      expect(publication.knownBlobShas, contains('sha-readme'));
    });

    for (final (label, record) in [
      (
        'an unproven (deployed) record',
        _copy(liveRecord, state: PublishState.deployed),
      ),
      ('a retired record', _copy(liveRecord, state: PublishState.retired)),
      ('a record of another repository', _copy(liveRecord, repo: 'me/other')),
      ('a record of another branch', _copy(liveRecord, branch: 'gh-pages')),
      ('a record without a head (legacy)', _copy(liveRecord, headSha: '')),
      ('a record adopted from a backup', liveRecord.asAdoptedFromBackup()),
    ]) {
      test('$label reads the whole tree', () async {
        final (publication, api) = await reconcile(record);

        expect(api.treeReads, 1, reason: label);
        expect(publication.treeRead, isTrue);
        expect(publication.knownBlobShas, contains('sha-readme'));
      });
    }

    test("after the read, an adopted record is this phone's own", () async {
      final (publication, _) = await reconcile(
        liveRecord.asAdoptedFromBackup(),
      );

      expect(publication.manifest.adoptedFromBackup, isFalse);
      expect(publication.manifest.state, PublishState.live);
    });

    test('the record it returns equals what a full read returns, for every '
        'combination of the reconciled fields', () async {
      var cases = 0;
      for (final keyed in [true, false]) {
        for (final rendition in [1, null]) {
          for (final proven in [true, false]) {
            for (final owned in [true, false]) {
              for (final files in const [
                {'books.json': 'sha-books', 'covers/1.jpg': 'sha-cover'},
                {'covers/1.jpg': 'sha-cover', 'events.json': 'sha-events'},
                <String, String>{},
              ]) {
                final local = PublishManifest(
                  repo: 'me/lib',
                  branch: 'main',
                  headSha: 'head-a',
                  ownershipConfirmed: owned,
                  state: PublishState.live,
                  fileShas: files,
                  coverUrlByBookId: const {'1': 'covers/a.jpg'},
                  proofPath: proven ? PublishProofPath.booksJson : null,
                  catalogueKeyed: keyed,
                  coverRendition: rendition,
                  committedAt: proven ? 5 : null,
                );
                // The real tree at head-a: the recorded files plus a file
                // a human added (a commit fixes ALL of this).
                final tree = snapshot(
                  files: {...files, 'README.md': 'sha-readme'},
                );
                final api = _Api(snapshot: tree);
                final skipped = (await GitHubPublicationReconciler(api).call(
                  target: target,
                  branch: 'main',
                  token: 'TKN',
                  local: local,
                )).toNullable()!;
                final full = local.reconciledFrom(
                  tree: tree,
                  ownerRepo: 'me/lib',
                  branch: 'main',
                );

                final label =
                    'keyed=$keyed rendition=$rendition '
                    'proven=$proven owned=$owned files=${files.keys}';
                expect(api.treeReads, 0, reason: label);
                expect(skipped.manifest.toJson(), full.toJson(), reason: label);
                expect(
                  tree.blobShas.containsAll(skipped.knownBlobShas),
                  isTrue,
                  reason: '$label: only blobs the branch holds',
                );
                cases++;
              }
            }
          }
        }
      }
      expect(cases, 48);
    });
  });
}

/// [record] with the given identity fields replaced (an empty [headSha]
/// means "none").
PublishManifest _copy(
  PublishManifest record, {
  String? repo,
  String? branch,
  String? headSha,
  PublishState? state,
}) => PublishManifest(
  repo: repo ?? record.repo,
  branch: branch ?? record.branch,
  headSha: headSha == '' ? null : headSha ?? record.headSha,
  ownershipConfirmed: record.ownershipConfirmed,
  state: state ?? record.state,
  fileShas: record.fileShas,
  coverUrlByBookId: record.coverUrlByBookId,
  proofPath: record.proofPath,
  catalogueKeyed: record.catalogueKeyed,
  coverRendition: record.coverRendition,
  committedAt: record.committedAt,
);
