import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

/// SPECIFICATION of the Cloudflare publish record (Cloudflare plan R5/R7/E.5,
/// J.1).
///
/// The point of these tests: the record decides which files survive a deploy,
/// so it must (a) claim nothing for a target it does not describe, (b) keep the
/// other section when one section is republished, and (c) never pretend a hash
/// it cannot trust is usable.
void main() {
  final target = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'kadugodi',
  )!;

  CloudflareAssetEntry entry(
    String sha, {
    String? hash,
    int size = 10,
    CloudflareContentType type = CloudflareContentType.json,
  }) => CloudflareAssetEntry(
    sha: sha,
    hash: hash ?? CloudflareAssetHash.of(const [1, 2, 3], type.extension),
    size: size,
    type: type,
  );

  CloudflareSiteManifest live({
    Map<String, CloudflareAssetEntry>? files,
    String? hashScheme = CloudflareAssetHash.scheme,
    Map<String, String> covers = const {},
  }) => CloudflareSiteManifest(
    target: target,
    state: PublishState.live,
    publishId: 'a' * 32,
    hashScheme: hashScheme,
    files:
        files ??
        {
          'books.json': entry('sha-books'),
          'index.html': entry('sha-index', type: CloudflareContentType.html),
          'pitak-publish.json': entry('sha-marker'),
        },
    coverUrlByBookId: covers,
  );

  group('target identity', () {
    test('describes only its own account, Worker and derived address', () {
      final manifest = live();

      expect(manifest.describes(target), isTrue);
      expect(
        manifest.describes(
          CloudflarePublishTarget.create(
            accountId: 'ffffffffffffffffffffffffffffffff',
            workerName: 'kadugodi-library',
            accountSubdomain: 'kadugodi',
          )!,
        ),
        isFalse,
      );
      expect(
        manifest.describes(
          CloudflarePublishTarget.create(
            accountId: '0123456789abcdef0123456789abcdef',
            workerName: 'other-worker',
            accountSubdomain: 'kadugodi',
          )!,
        ),
        isFalse,
      );
    });

    test('the empty record describes nothing', () {
      expect(CloudflareSiteManifest.empty.describes(target), isFalse);
      expect(CloudflareSiteManifest.empty.ownedPaths, isEmpty);
    });
  });

  group('JSON round trip', () {
    test('keeps the target, state, publish id, scheme, files and covers', () {
      final manifest = live(covers: {'42': 'https://covers.example/42.jpg'});

      final decoded = CloudflareSiteManifest.fromJson(manifest.toJson());

      expect(decoded.describes(target), isTrue);
      expect(decoded.state, PublishState.live);
      expect(decoded.publishId, 'a' * 32);
      expect(decoded.hashScheme, CloudflareAssetHash.scheme);
      expect(decoded.shaFor('books.json'), 'sha-books');
      expect(decoded.coverSourceFor('42'), 'https://covers.example/42.jpg');
      expect(decoded.files['books.json']!.type, CloudflareContentType.json);
    });

    test(
      'a record whose stored URL disagrees with its parts claims nothing',
      () {
        final json = live().toJson();
        (json['target']! as Map<String, Object?>)['siteUrl'] =
            'https://evil.example/';

        final decoded = CloudflareSiteManifest.fromJson(json);

        expect(decoded.target, isNull);
        expect(decoded.ownedPaths, isEmpty);
      },
    );

    test('a record with no target claims nothing', () {
      expect(
        CloudflareSiteManifest.fromJson({
          'schema': 2,
          'files': <String, Object?>{},
        }).ownedPaths,
        isEmpty,
      );
    });

    test('an unknown state invalidates the whole record', () {
      final json = live().toJson()..['state'] = 'something-new';

      final decoded = CloudflareSiteManifest.fromJson(json);

      expect(decoded.target, isNull);
      expect(decoded.ownedPaths, isEmpty);
    });

    test('an unsupported schema invalidates the whole record', () {
      final json = live().toJson()..['schema'] = 1;

      expect(CloudflareSiteManifest.fromJson(json).target, isNull);
    });

    test('a missing or malformed publish id invalidates the whole record', () {
      for (final value in [null, 'not-a-publish-id']) {
        final json = live().toJson()..['publishId'] = value;
        expect(CloudflareSiteManifest.fromJson(json).target, isNull);
      }
    });

    test('a malformed file entry invalidates the whole record', () {
      final json = live().toJson();
      (json['files']! as Map<String, Object?>)['broken.json'] = {
        'sha': 'x',
        'hash': 'too-short',
        'size': 1,
        'type': 'application/json',
      };

      final decoded = CloudflareSiteManifest.fromJson(json);

      expect(decoded.target, isNull);
      expect(decoded.ownedPaths, isEmpty);
    });

    test('an unsafe or type-mismatched path invalidates the whole record', () {
      for (final path in ['../escape.json', 'books.html', 'unknown.json']) {
        final json = live().toJson();
        final files = json['files']! as Map<String, Object?>;
        final books = files.remove('books.json');
        if (books == null) fail('books.json fixture missing');
        files[path] = books;

        final decoded = CloudflareSiteManifest.fromJson(json);

        expect(decoded.target, isNull, reason: path);
        expect(decoded.ownedPaths, isEmpty, reason: path);
      }
    });
  });

  group('state-specific file sets', () {
    test('normal records require the marker and catalogue core', () {
      const core = {'books.json', 'index.html', 'pitak-publish.json'};
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.live,
          paths: core,
        ),
        isTrue,
      );
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.deployed,
          paths: core.difference({'pitak-publish.json'}),
        ),
        isFalse,
      );
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.live,
          paths: {...core, '404.html'},
        ),
        isFalse,
      );
    });

    test('events files are coherent and posters cannot stand alone', () {
      const core = {'books.json', 'index.html', 'pitak-publish.json'};
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.live,
          paths: {...core, 'events.json'},
        ),
        isFalse,
      );
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.live,
          paths: {...core, 'posters/a.jpg'},
        ),
        isFalse,
      );
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.live,
          paths: {...core, 'events.html', 'events.json', 'posters/a.jpg'},
        ),
        isTrue,
      );
    });

    test('retired records are exactly the moved-page set', () {
      const moved = {'index.html', '404.html', 'pitak-publish.json'};
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.retired,
          paths: moved,
        ),
        isTrue,
      );
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.retired,
          paths: {...moved, 'books.json'},
        ),
        isFalse,
      );
    });
  });

  group('hashScheme', () {
    test('a different scheme keeps the paths but not the hashes', () {
      final manifest = live(hashScheme: 'blake3-b64-ext-32');

      expect(manifest.hashesTrusted, isFalse);
      expect(manifest.ownedPaths, contains('books.json'));
    });

    test('a missing scheme is not trusted', () {
      expect(live(hashScheme: null).hashesTrusted, isFalse);
    });
  });

  group('state transitions', () {
    test('afterDeploy records the complete snapshot as deployed', () {
      final manifest = live().afterDeploy(
        publishId: 'b' * 32,
        files: {'books.json': entry('sha-books')},
        coverUrlByBookId: const {},
      );

      expect(manifest.state, PublishState.deployed);
      expect(manifest.publishId, 'b' * 32);
      expect(manifest.hashScheme, CloudflareAssetHash.scheme);
    });

    test('asLive keeps everything else', () {
      final manifest = live().asLive();

      expect(manifest.state, PublishState.live);
      expect(manifest.publishId, 'a' * 32);
      expect(manifest.shaFor('books.json'), 'sha-books');
    });

    test('asRetired replaces the file map with the moved files', () {
      final manifest = live().asRetired(
        publishId: 'c' * 32,
        files: {'index.html': entry('sha-moved')},
      );

      expect(manifest.state, PublishState.retired);
      expect(manifest.publishId, 'c' * 32);
      expect(manifest.ownedPaths, ['index.html']);
    });
  });

  group('section merge', () {
    PublishFile file(String path, String sha) =>
        PublishFile(path: path, bytes: const [], gitSha: sha, upload: false);

    test('a catalogue update carries every events path forward', () {
      final previous = live(
        files: {
          'books.json': entry('sha-books-old'),
          'posters/a.jpg': entry('sha-poster-a'),
          'events.json': entry('sha-events'),
        },
      );
      final merge = mergeSection(
        previous: previous,
        section: PublishSection(
          section: SiteSection.catalogue,
          files: [file('books.json', 'sha-books-new')],
        ),
      );

      final result = previous.mergedWith(
        merge: merge,
        built: {'books.json': entry('sha-books-new')},
      );

      expect(result.missingHashes, isEmpty);
      expect(
        result.files.keys,
        containsAll(<String>['books.json', 'posters/a.jpg', 'events.json']),
      );
      expect(result.files['books.json']!.sha, 'sha-books-new');
      expect(result.files['posters/a.jpg']!.sha, 'sha-poster-a');
    });

    test('a dropped poster leaves the snapshot entirely', () {
      final previous = live(
        files: {
          'books.json': entry('sha-books'),
          'posters/a.jpg': entry('sha-poster-a'),
          'posters/b.jpg': entry('sha-poster-b'),
        },
      );
      final merge = mergeSection(
        previous: previous,
        section: PublishSection(
          section: SiteSection.events,
          files: [file('posters/b.jpg', 'sha-poster-b')],
        ),
      );

      final result = previous.mergedWith(merge: merge, built: {});

      expect(result.files.keys, isNot(contains('posters/a.jpg')));
      expect(result.files.keys, contains('posters/b.jpg'));
      expect(result.files.keys, contains('books.json'));
    });

    test('an untrusted hash is reported, never reused', () {
      final previous = live(
        hashScheme: 'blake3-b64-ext-32',
        files: {
          'books.json': entry('sha-books'),
          'posters/a.jpg': entry('sha-poster-a'),
        },
      );
      final merge = mergeSection(
        previous: previous,
        section: PublishSection(
          section: SiteSection.catalogue,
          files: [file('books.json', 'sha-books')],
        ),
      );

      final result = previous.mergedWith(
        merge: merge,
        built: {'books.json': entry('sha-books')},
      );

      expect(result.missingHashes, ['posters/a.jpg']);
      expect(result.files.keys, isNot(contains('posters/a.jpg')));
    });

    test('a carried path whose recorded sha changed is reported', () {
      final previous = live(
        files: {
          'books.json': entry('sha-books'),
          'posters/a.jpg': entry('sha-poster-a'),
        },
      );
      // The merge says the poster's content sha is now different, but no built
      // entry was supplied for it: the recorded hash cannot be trusted.
      final merge = mergeSection(
        previous: previous,
        section: PublishSection(
          section: SiteSection.events,
          files: [file('posters/a.jpg', 'sha-poster-a-new')],
        ),
      );

      final result = previous.mergedWith(merge: merge, built: {});

      expect(result.missingHashes, ['posters/a.jpg']);
    });

    test('cover-source metadata survives a section update', () {
      final previous = live(covers: {'42': 'https://covers.example/42.jpg'});
      final merge = mergeSection(
        previous: previous,
        section: PublishSection(
          section: SiteSection.catalogue,
          files: [file('books.json', 'sha-books')],
        ),
      );

      final next = previous.afterDeploy(
        publishId: 'd' * 32,
        files: previous.mergedWith(merge: merge, built: {}).files,
        coverUrlByBookId: previous.coverUrlByBookId,
      );

      expect(next.coverSourceFor('42'), 'https://covers.example/42.jpg');
    });
  });
}
