import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
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
        coverRendition: null,
        proofPath: PublishProofPath.booksJson,
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

    test('asLive keeps the ADR 0019 fields', () {
      const committed = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'h',
        fileShas: {'books.json': 'sha'},
        proofPath: PublishProofPath.booksJson,
        catalogueKeyed: true,
      );
      final live = committed.asLive();
      expect(live.proofPath, PublishProofPath.booksJson);
      expect(live.catalogueKeyed, isTrue);
    });

    test('asRetired drops keys and proof (a moved page has neither)', () {
      const live = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'h',
        state: PublishState.live,
        fileShas: {'books.json': 'sha'},
        proofPath: PublishProofPath.booksJson,
        catalogueKeyed: true,
      );
      final retired = live.asRetired(
        commitSha: 'r',
        movedFileShas: {'index.html': 'm'},
      );
      expect(retired.catalogueKeyed, isFalse);
      expect(retired.proofPath, isNull);
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

  group('ADR 0019: proofPath', () {
    Map<String, dynamic> stored({
      Object? proof,
      bool includeProof = true,
      String state = 'deployed',
      Map<String, String> files = const {'books.json': 'b', 'events.json': 'e'},
    }) => {
      'schema': 2,
      'repo': 'me/lib',
      'branch': 'main',
      'headSha': 'head-a',
      'ownershipConfirmed': true,
      'state': state,
      'fileShas': files,
      'coverUrlByBookId': <String, String>{},
      if (includeProof) 'proofPath': proof,
    };

    test('round-trips every proof through JSON', () {
      for (final proof in PublishProofPath.values) {
        final files = proof.expectsAbsent
            ? const {'books.json': 'b'}
            : {proof.path: 'x', 'books.json': 'b'};
        final manifest = PublishManifest(
          repo: 'me/lib',
          branch: 'main',
          headSha: 'h',
          fileShas: files,
          proofPath: proof,
        );
        final json = manifest.toJson();
        expect(json['proofPath'], proof.name);
        expect(PublishManifest.fromJson(json).proofPath, proof);
      }
    });

    test('a record without the field reads as null (per-section file)', () {
      final decoded = PublishManifest.fromJson(stored(includeProof: false));
      expect(decoded.proofPath, isNull);
      expect(decoded.headSha, 'head-a');
      expect(PublishManifest.empty.toJson().containsKey('proofPath'), isFalse);
    });

    test('an unknown proof forgets the head of an unproven record', () {
      // No later check may "prove" this commit through a guessed file
      // (plan A.1 item 8): it reads like a legacy record in unknown state.
      for (final bad in ['somethingNew', 7, null]) {
        final decoded = PublishManifest.fromJson(stored(proof: bad));
        expect(decoded.proofPath, isNull, reason: '$bad');
        expect(decoded.headSha, isNull, reason: '$bad');
        expect(decoded.state, PublishState.deployed, reason: '$bad');
        // Ownership is untouched: the paths are still ours to delete.
        expect(decoded.ownedPaths, containsAll(['books.json', 'events.json']));
      }
    });

    test('a proof that contradicts the record files is unreadable', () {
      final expectedButMissing = PublishManifest.fromJson(
        stored(proof: 'availabilityJson'),
      );
      expect(expectedButMissing.proofPath, isNull);
      expect(expectedButMissing.headSha, isNull);

      final absentButRecorded = PublishManifest.fromJson(
        stored(
          proof: 'availabilityJsonAbsent',
          files: const {'books.json': 'b', 'availability.json': 'a'},
        ),
      );
      expect(absentButRecorded.proofPath, isNull);
      expect(absentButRecorded.headSha, isNull);
    });

    test('a settled (live) record keeps its head when the proof is bad', () {
      final decoded = PublishManifest.fromJson(
        stored(proof: 'somethingNew', state: 'live'),
      );
      expect(decoded.state, PublishState.live);
      expect(decoded.headSha, 'head-a');
      expect(decoded.proofPath, isNull);
    });

    test('reconciliation keeps the proof only for the same head', () {
      const local = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'head-a',
        ownershipConfirmed: true,
        fileShas: {'availability.json': 'a', 'books.json': 'b'},
        proofPath: PublishProofPath.availabilityJson,
      );
      final files = {'availability.json': 'a', 'books.json': 'b'};
      expect(
        local
            .reconciledFrom(
              tree: tree(files),
              ownerRepo: 'me/lib',
              branch: 'main',
            )
            .proofPath,
        PublishProofPath.availabilityJson,
      );
      expect(
        local
            .reconciledFrom(
              tree: tree(files, head: 'head-b'),
              ownerRepo: 'me/lib',
              branch: 'main',
            )
            .proofPath,
        isNull,
      );
      expect(
        local
            .reconciledFrom(
              tree: tree(files, branch: 'gh-pages'),
              ownerRepo: 'me/lib',
              branch: 'gh-pages',
            )
            .proofPath,
        isNull,
      );
    });

    group('afterCommit (S4: every commit records its proof)', () {
      const local = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'old-head',
        proofPath: PublishProofPath.eventsJson,
        fileShas: {'books.json': 'b', 'events.json': 'e'},
      );

      test('records the proof of THIS commit, replacing the old one', () {
        final cases = {
          PublishProofPath.booksJson: {'books.json': 'b2', 'events.json': 'e'},
          PublishProofPath.eventsJson: {'books.json': 'b', 'events.json': 'e2'},
          PublishProofPath.availabilityJson: {
            'books.json': 'b',
            'events.json': 'e',
            'availability.json': 'a',
          },
          PublishProofPath.availabilityJsonAbsent: {
            'books.json': 'b',
            'events.json': 'e',
          },
        };
        for (final MapEntry(key: proof, value: merged) in cases.entries) {
          final committed = local.afterCommit(
            commitSha: 'c',
            mergedShas: merged,
            coverUrlByBookId: const {},
            coverRendition: null,
            proofPath: proof,
          );
          expect(committed.proofPath, proof, reason: proof.name);
          expect(committed.headSha, 'c', reason: proof.name);
          expect(committed.state, PublishState.deployed, reason: proof.name);
          // It survives a save and a load unchanged.
          final reloaded = PublishManifest.fromJson(committed.toJson());
          expect(reloaded.proofPath, proof, reason: proof.name);
          expect(reloaded.headSha, 'c', reason: proof.name);
        }
      });

      test('a proof that contradicts the commit forgets head and proof', () {
        // Only a caller bug can do this; the record then reads like a
        // legacy one in unknown state, exactly as a damaged stored proof
        // does, so no check can "prove" the commit through a wrong file.
        final missingFile = local.afterCommit(
          commitSha: 'c',
          mergedShas: {'books.json': 'b'},
          coverUrlByBookId: const {},
          coverRendition: null,
          proofPath: PublishProofPath.eventsJson,
        );
        expect(missingFile.proofPath, isNull);
        expect(missingFile.headSha, isNull);
        expect(missingFile.fileShas, {'books.json': 'b'});

        final stillRecorded = local.afterCommit(
          commitSha: 'c',
          mergedShas: {'books.json': 'b', 'availability.json': 'a'},
          coverUrlByBookId: const {},
          coverRendition: null,
          proofPath: PublishProofPath.availabilityJsonAbsent,
        );
        expect(stillRecorded.proofPath, isNull);
        expect(stillRecorded.headSha, isNull);
      });
    });
  });

  group('ADR 0019: catalogueKeyed', () {
    const keyed = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'head-a',
      ownershipConfirmed: true,
      fileShas: {'books.json': 'keyed-books', 'events.json': 'e'},
      catalogueKeyed: true,
    );

    test('round-trips through JSON', () {
      final json = keyed.toJson();
      expect(json['catalogueKeyed'], isTrue);
      expect(PublishManifest.fromJson(json).catalogueKeyed, isTrue);
    });

    test('an older record without the field reads as false', () {
      final json = keyed.toJson()..remove('catalogueKeyed');
      expect(PublishManifest.fromJson(json).catalogueKeyed, isFalse);
      expect(PublishManifest.empty.catalogueKeyed, isFalse);
    });

    test('anything but a stored true reads as false', () {
      for (final value in ['true', 1, null, false]) {
        final json = keyed.toJson()..['catalogueKeyed'] = value;
        expect(
          PublishManifest.fromJson(json).catalogueKeyed,
          isFalse,
          reason: '$value',
        );
      }
    });

    test('a keyed claim without a recorded books.json reads as false', () {
      final json = keyed.toJson()
        ..['fileShas'] = <String, String>{'events.json': 'e'};
      expect(PublishManifest.fromJson(json).catalogueKeyed, isFalse);
    });

    group('reconciledFrom (gate 7b, plan A.6 #19)', () {
      test("survives while the branch holds this phone's books.json", () {
        final reconciled = keyed.reconciledFrom(
          tree: tree({'books.json': 'keyed-books', 'events.json': 'e2'}),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(reconciled.catalogueKeyed, isTrue);
      });

      test("another writer's books.json clears it (other salt or old app)", () {
        final reconciled = keyed.reconciledFrom(
          tree: tree({'books.json': 'someone-else', 'events.json': 'e'}),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(reconciled.catalogueKeyed, isFalse);
      });

      test('a deleted books.json clears it', () {
        final reconciled = keyed.reconciledFrom(
          tree: tree({'events.json': 'e'}),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(reconciled.catalogueKeyed, isFalse);
      });

      test('another repo or branch never inherits it', () {
        for (final (repo, branch) in [('me/other', 'main'), ('me/lib', 'gh')]) {
          final reconciled = keyed.reconciledFrom(
            tree: tree(
              {'books.json': 'keyed-books'},
              repo: repo,
              branch: branch,
            ),
            ownerRepo: repo,
            branch: branch,
          );
          expect(reconciled.catalogueKeyed, isFalse, reason: '$repo@$branch');
        }
      });
    });

    group('afterCommit', () {
      test('a commit that wrote a keyed books.json sets it', () {
        const unkeyed = PublishManifest(repo: 'me/lib', branch: 'main');
        final committed = unkeyed.afterCommit(
          commitSha: 'c',
          mergedShas: {'books.json': 'new-books'},
          coverUrlByBookId: const {},
          coverRendition: null,
          wroteKeyedCatalogue: true,
          proofPath: PublishProofPath.booksJson,
        );
        expect(committed.catalogueKeyed, isTrue);
      });

      test('an events commit that left books.json alone keeps it', () {
        final committed = keyed.afterCommit(
          commitSha: 'c',
          mergedShas: {'books.json': 'keyed-books', 'events.json': 'e2'},
          coverUrlByBookId: const {},
          coverRendition: null,
          proofPath: PublishProofPath.eventsJson,
        );
        expect(committed.catalogueKeyed, isTrue);
      });

      test('an availability commit keeps it (books.json untouched)', () {
        final committed = keyed.afterCommit(
          commitSha: 'c',
          mergedShas: {
            'books.json': 'keyed-books',
            'events.json': 'e',
            'availability.json': 'a',
          },
          coverUrlByBookId: const {},
          coverRendition: null,
          proofPath: PublishProofPath.availabilityJson,
        );
        expect(committed.catalogueKeyed, isTrue);
      });

      test('a commit that wrote an unkeyed books.json clears it', () {
        final committed = keyed.afterCommit(
          commitSha: 'c',
          mergedShas: {'books.json': 'unkeyed-books'},
          coverUrlByBookId: const {},
          coverRendition: null,
          proofPath: PublishProofPath.booksJson,
        );
        expect(committed.catalogueKeyed, isFalse);
      });

      test('no books.json means not keyed, whatever the caller says', () {
        final committed = keyed.afterCommit(
          commitSha: 'c',
          mergedShas: {'events.json': 'e'},
          coverUrlByBookId: const {},
          coverRendition: null,
          wroteKeyedCatalogue: true,
          proofPath: PublishProofPath.eventsJson,
        );
        expect(committed.catalogueKeyed, isFalse);
      });
    });
  });

  group('withoutCatalogueKeys (plan J9)', () {
    test('clears only the flag; files, head, proof and state stay', () {
      const keyed = PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'head-a',
        ownershipConfirmed: true,
        state: PublishState.live,
        fileShas: {'books.json': 'b1', 'availability.json': 'a1'},
        coverUrlByBookId: {'7': 'https://example.org/c.jpg'},
        proofPath: PublishProofPath.availabilityJson,
        catalogueKeyed: true,
      );
      final cleared = keyed.withoutCatalogueKeys();
      expect(cleared.catalogueKeyed, isFalse);
      expect(cleared.repo, 'me/lib');
      expect(cleared.branch, 'main');
      expect(cleared.headSha, 'head-a');
      expect(cleared.ownershipConfirmed, isTrue);
      expect(cleared.state, PublishState.live);
      expect(cleared.fileShas, keyed.fileShas);
      expect(cleared.coverUrlByBookId, keyed.coverUrlByBookId);
      expect(cleared.proofPath, PublishProofPath.availabilityJson);
      expect(
        PublishManifest.fromJson(cleared.toJson()).catalogueKeyed,
        isFalse,
      );
    });
  });

  group('ADR 0020: coverRendition', () {
    const covered = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'head-a',
      ownershipConfirmed: true,
      state: PublishState.live,
      fileShas: {
        'books.json': 'b',
        'covers/aaaa.jpg': 'cover-a',
        'covers/bbbb.jpg': 'cover-b',
      },
      coverUrlByBookId: {
        '1': 'covers/one.jpg',
        '2': 'file:///data/user/0/app/covers/two.jpg',
        '3': 'https://covers.openlibrary.org/b/id/3-L.jpg',
        'periodical:uid-1': 'covers/series.jpg',
      },
      catalogueKeyed: true,
      coverRendition: PublishCoverRendition.current,
    );

    test('round-trips through JSON; the builders see it', () {
      final json = covered.toJson();
      expect(json['coverRendition'], PublishCoverRendition.current);
      final back = PublishManifest.fromJson(json);
      expect(back.coverRendition, PublishCoverRendition.current);
      expect(back.reusableCoverRendition, PublishCoverRendition.current);
    });

    test('absent or malformed reads as unknown (every cover produced '
        'again), and an unknown rendition is not written', () {
      final json = covered.toJson()..remove('coverRendition');
      expect(PublishManifest.fromJson(json).coverRendition, isNull);
      for (final bad in <Object?>['1', 0, -2, 1.5, true]) {
        final damaged = covered.toJson()..['coverRendition'] = bad;
        expect(
          PublishManifest.fromJson(damaged).coverRendition,
          isNull,
          reason: '$bad',
        );
      }
      expect(
        PublishManifest.empty.toJson().containsKey('coverRendition'),
        isFalse,
      );
    });

    test('afterCommit stores exactly the rendition it is given', () {
      final catalogue = covered.afterCommit(
        commitSha: 'c',
        mergedShas: covered.fileShas,
        coverUrlByBookId: covered.coverUrlByBookId,
        coverRendition: PublishCoverRendition.current,
        proofPath: PublishProofPath.booksJson,
      );
      expect(catalogue.coverRendition, PublishCoverRendition.current);
      final unknown = covered.afterCommit(
        commitSha: 'c',
        mergedShas: covered.fileShas,
        coverUrlByBookId: covered.coverUrlByBookId,
        coverRendition: null,
        proofPath: PublishProofPath.booksJson,
      );
      expect(unknown.coverRendition, isNull);
    });

    test('asLive and withoutCatalogueKeys keep it; asRetired drops it', () {
      expect(covered.asLive().coverRendition, PublishCoverRendition.current);
      expect(
        covered.withoutCatalogueKeys().coverRendition,
        PublishCoverRendition.current,
      );
      final retired = covered.asRetired(
        commitSha: 'r',
        movedFileShas: const {'index.html': 'moved'},
      );
      expect(retired.coverRendition, isNull, reason: 'no covers any more');
    });

    group('reconciledFrom', () {
      test('same site, covers untouched: kept', () {
        final next = covered.reconciledFrom(
          tree: tree(covered.fileShas),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(next.coverRendition, PublishCoverRendition.current);
      });

      test('a recorded cover that is gone just drops out: kept', () {
        final next = covered.reconciledFrom(
          tree: tree({'books.json': 'b', 'covers/aaaa.jpg': 'cover-a'}),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(next.coverRendition, PublishCoverRendition.current);
        expect(next.shaFor('covers/bbbb.jpg'), isNull);
      });

      test('someone else changed one cover on the branch: unknown, so the '
          'next publish produces every cover and puts ours back', () {
        final next = covered.reconciledFrom(
          tree: tree({...covered.fileShas, 'covers/bbbb.jpg': 'edited'}),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(next.coverRendition, isNull);
        expect(next.reusableCoverRendition, isNull);
        expect(next.shaFor('covers/bbbb.jpg'), 'edited');
      });

      test('a change to a non-cover file does not touch it', () {
        final next = covered.reconciledFrom(
          tree: tree({...covered.fileShas, 'books.json': 'other'}),
          ownerRepo: 'me/lib',
          branch: 'main',
        );
        expect(next.coverRendition, PublishCoverRendition.current);
      });

      test('another repo or branch: unknown (the record claims nothing)', () {
        for (final (repo, branch) in [('me/other', 'main'), ('me/lib', 'gh')]) {
          final next = covered.reconciledFrom(
            tree: tree(covered.fileShas, repo: repo, branch: branch),
            ownerRepo: repo,
            branch: branch,
          );
          expect(next.coverRendition, isNull, reason: '$repo@$branch');
        }
      });
    });

    group('withoutLocalCoverSources (ADR 0020 Decision 4)', () {
      test('forgets covers/ and file:// sources, keeps remote ones and '
          'everything else', () {
        expect(covered.hasLocalCoverSources, isTrue);
        final next = covered.withoutLocalCoverSources();
        expect(next.coverUrlByBookId, {
          '3': 'https://covers.openlibrary.org/b/id/3-L.jpg',
        });
        expect(next.hasLocalCoverSources, isFalse);
        expect(next.fileShas, covered.fileShas);
        expect(next.repo, covered.repo);
        expect(next.branch, covered.branch);
        expect(next.headSha, covered.headSha);
        expect(next.state, covered.state);
        expect(next.ownershipConfirmed, isTrue);
        expect(next.catalogueKeyed, isTrue);
        expect(next.coverRendition, PublishCoverRendition.current);
        expect(next.proofPath, covered.proofPath);
      });

      test('a record with remote covers only has nothing to forget', () {
        const remoteOnly = PublishManifest(
          coverUrlByBookId: {'1': 'https://example.org/1.jpg'},
        );
        expect(remoteOnly.hasLocalCoverSources, isFalse);
        expect(PublishManifest.empty.hasLocalCoverSources, isFalse);
      });
    });
  });
}
