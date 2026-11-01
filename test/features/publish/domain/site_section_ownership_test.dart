import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

/// SPECIFICATION of section ownership after ADR 0019 (plan C.2 item 1).
///
/// The availability section owns EXACTLY `availability.json`: no other
/// section may write or delete it, and it may touch nothing else.
void main() {
  group('SiteSection.availability', () {
    test('owns availability.json and nothing else', () {
      expect(SiteSection.availability.owns('availability.json'), isTrue);
      for (final path in [
        'books.json',
        'index.html',
        'library.json',
        'events.json',
        'events.html',
        '404.html',
        'pitak-publish.json',
        'covers/availability.json',
        'availability.json.bak',
        'availability.JSON',
        '../availability.json',
      ]) {
        expect(SiteSection.availability.owns(path), isFalse, reason: path);
      }
    });

    test('no other section owns availability.json — not even retirement', () {
      for (final section in SiteSection.values) {
        if (section == SiteSection.availability) continue;
        expect(
          section.owns('availability.json'),
          isFalse,
          reason: section.name,
        );
      }
    });
  });

  group('anyOwns: the one app-owned-path rule', () {
    test('accepts every section file, including availability.json', () {
      for (final path in [
        'books.json',
        'index.html',
        'library.json',
        'covers/a.jpg',
        'events.html',
        'events.json',
        'posters/a.jpg',
        '404.html',
        'pitak-publish.json',
        'availability.json',
      ]) {
        expect(SiteSection.anyOwns(path), isTrue, reason: path);
      }
    });

    test('refuses unknown and unsafe paths', () {
      for (final path in ['README.md', 'notes/x.txt', '../books.json', '']) {
        expect(SiteSection.anyOwns(path), isFalse, reason: path);
      }
    });

    test('the Cloudflare record uses the same rule', () {
      expect(CloudflareSiteManifest.isAllowedPath('availability.json'), isTrue);
      expect(CloudflareSiteManifest.isAllowedPath('unknown.json'), isFalse);
    });
  });

  group('merging around availability.json', () {
    PublishFile file(String path, String sha) =>
        PublishFile(path: path, bytes: const [1], gitSha: sha, upload: true);

    test('a catalogue publish keeps a live availability.json', () {
      final merge = mergeSection(
        previous: _Previous({'books.json': 'b1', 'availability.json': 'a1'}),
        section: PublishSection(
          section: SiteSection.catalogue,
          files: [file('books.json', 'b2')],
        ),
      );
      expect(merge.fileShas, {'books.json': 'b2', 'availability.json': 'a1'});
      expect(merge.deletePaths, isEmpty);
    });

    test('an availability publish changes only availability.json', () {
      final merge = mergeSection(
        previous: _Previous({
          'books.json': 'b1',
          'events.json': 'e1',
          'availability.json': 'a1',
        }),
        section: PublishSection(
          section: SiteSection.availability,
          files: [file('availability.json', 'a2')],
        ),
      );
      expect(merge.fileShas, {
        'books.json': 'b1',
        'events.json': 'e1',
        'availability.json': 'a2',
      });
      expect(merge.deletePaths, isEmpty);
    });

    test('an availability removal deletes exactly availability.json', () {
      final merge = mergeSection(
        previous: _Previous({'books.json': 'b1', 'availability.json': 'a1'}),
        section: const PublishSection(
          section: SiteSection.availability,
          files: [],
          deletePaths: ['availability.json'],
        ),
      );
      expect(merge.fileShas, {'books.json': 'b1'});
      expect(merge.deletePaths, ['availability.json']);
    });

    test('the availability section cannot write or delete other files', () {
      final merge = mergeSection(
        previous: _Previous({'books.json': 'b1'}),
        section: PublishSection(
          section: SiteSection.availability,
          files: [file('books.json', 'evil')],
          deletePaths: const ['books.json'],
        ),
      );
      expect(merge.fileShas, {'books.json': 'b1'});
      expect(merge.deletePaths, isEmpty);
    });
  });

  group('Cloudflare file sets with availability.json (plan C.2 item 6)', () {
    const core = {'books.json', 'index.html', 'pitak-publish.json'};

    test('a normal set may contain availability.json', () {
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.live,
          paths: {...core, 'availability.json'},
        ),
        isTrue,
      );
    });

    test('a retired set never contains it', () {
      expect(
        CloudflareSiteManifest.isValidFileSet(
          state: PublishState.retired,
          paths: const {
            'index.html',
            '404.html',
            'pitak-publish.json',
            'availability.json',
          },
        ),
        isFalse,
      );
    });
  });
}

class _Previous implements PreviousPublication {
  _Previous(this.shas);

  final Map<String, String> shas;

  @override
  String? shaFor(String path) => shas[path];

  @override
  String? coverSourceFor(String key) => null;

  @override
  Iterable<String> get ownedPaths => shas.keys;
}
