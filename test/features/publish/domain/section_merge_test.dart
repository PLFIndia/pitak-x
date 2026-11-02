import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

/// R7/R8/M14: ONE section merge. A publish of one section must never erase
/// the other, and deletions are exact, owned paths — never a prefix sweep.
void main() {
  PublishFile file(String path, {String sha = 'sha', bool upload = true}) =>
      PublishFile(path: path, bytes: const [1], gitSha: sha, upload: upload);

  test('a catalogue update preserves every events path', () {
    final previous = _Previous({
      'events.html': 'e1',
      'events.json': 'e2',
      'posters/a.jpg': 'p1',
      'books.json': 'old-books',
      'index.html': 'old-index',
    });

    final merge = mergeSection(
      previous: previous,
      section: PublishSection(
        section: SiteSection.catalogue,
        files: [
          file('books.json', sha: 'new-books'),
          file('index.html', sha: 'new-index'),
        ],
      ),
    );

    expect(merge.fileShas, {
      'events.html': 'e1',
      'events.json': 'e2',
      'posters/a.jpg': 'p1',
      'books.json': 'new-books',
      'index.html': 'new-index',
    });
    expect(merge.deletePaths, isEmpty);
  });

  test('an events update preserves every catalogue path', () {
    final previous = _Previous({
      'books.json': 'b',
      'index.html': 'i',
      'covers/x.jpg': 'c',
      'events.json': 'old',
    });

    final merge = mergeSection(
      previous: previous,
      section: PublishSection(
        section: SiteSection.events,
        files: [
          file('events.json', sha: 'new'),
          file('events.html', sha: 'h'),
        ],
      ),
    );

    expect(
      merge.fileShas.keys,
      containsAll(['books.json', 'index.html', 'covers/x.jpg']),
    );
    expect(merge.fileShas['events.json'], 'new');
  });

  test('a removed poster becomes an EXACT deletion', () {
    final previous = _Previous({
      'posters/a.jpg': 'pa',
      'posters/b.jpg': 'pb',
      'books.json': 'b',
    });

    final merge = mergeSection(
      previous: previous,
      section: PublishSection(
        section: SiteSection.events,
        files: [
          file('events.html'),
          file('events.json'),
          file('posters/a.jpg', sha: 'pa', upload: false),
        ],
      ),
    );

    expect(merge.deletePaths, ['posters/b.jpg']);
    expect(merge.fileShas.containsKey('posters/b.jpg'), isFalse);
    expect(
      merge.fileShas['books.json'],
      'b',
      reason: 'other section untouched',
    );
  });

  test('an emptied events section deletes every poster it owned', () {
    final previous = _Previous({
      'posters/a.jpg': 'pa',
      'posters/b.jpg': 'pb',
      'events.html': 'h',
    });

    final merge = mergeSection(
      previous: previous,
      section: PublishSection(
        section: SiteSection.events,
        files: [
          file('events.html', sha: 'h', upload: false),
          file('events.json'),
        ],
      ),
    );

    expect(merge.deletePaths, ['posters/a.jpg', 'posters/b.jpg']);
  });

  test(
    'SECURITY: an unsafe previous path is ignored, never echoed as a delete',
    () {
      final previous = _Previous({
        '../evil': 'x',
        'covers/../../etc/passwd': 'y',
        '/abs.jpg': 'z',
        'books.json': 'b',
      });

      final merge = mergeSection(
        previous: previous,
        section: PublishSection(
          section: SiteSection.catalogue,
          files: [file('books.json', sha: 'b', upload: false)],
        ),
      );

      expect(merge.deletePaths, isEmpty);
      expect(merge.fileShas.keys, ['books.json']);
    },
  );

  test('a builder cannot write a path another section owns', () {
    final merge = mergeSection(
      previous: _Previous(const {}),
      section: PublishSection(
        section: SiteSection.catalogue,
        files: [file('posters/a.jpg'), file('books.json')],
      ),
    );

    expect(merge.fileShas.keys, ['books.json']);
  });

  group('mergeSections — several sections, ONE write (ADR 0019)', () {
    const catalogue = PublishSection(
      section: SiteSection.catalogue,
      files: [
        PublishFile(
          path: 'books.json',
          bytes: [1],
          gitSha: 'new-books',
          upload: true,
        ),
      ],
      deletePaths: ['library.json'],
    );

    test('catalogue + availability: every file, every deletion, one set', () {
      final previous = _Previous({
        'books.json': 'old-books',
        'library.json': 'old-descriptor',
        'events.json': 'keep-events',
      });
      final merge = mergeSections(
        previous: previous,
        sections: [
          catalogue,
          PublishSection(
            section: SiteSection.availability,
            files: [file('availability.json', sha: 'avail')],
          ),
        ],
      );

      expect(merge.files.map((f) => f.path), [
        'books.json',
        'availability.json',
      ]);
      expect(merge.deletePaths, ['library.json']);
      expect(merge.fileShas, {
        'events.json': 'keep-events',
        'books.json': 'new-books',
        'availability.json': 'avail',
      });
    });

    test('a removal rides along with the catalogue (A.6 #20)', () {
      final merge = mergeSections(
        previous: _Previous({
          'books.json': 'old-books',
          'availability.json': 'stale',
        }),
        sections: [
          catalogue,
          const PublishSection(
            section: SiteSection.availability,
            files: [],
            deletePaths: ['availability.json'],
          ),
        ],
      );
      // The catalogue's own deletion and the lane's removal, in one write.
      expect(merge.deletePaths, ['availability.json', 'library.json']);
      expect(merge.fileShas, {'books.json': 'new-books'});
    });

    test('the order of the sections does not change the record', () {
      final previous = _Previous({
        'books.json': 'old-books',
        'library.json': 'd',
        'availability.json': 'old-avail',
      });
      final availability = PublishSection(
        section: SiteSection.availability,
        files: [file('availability.json', sha: 'new-avail')],
      );
      final forward = mergeSections(
        previous: previous,
        sections: [catalogue, availability],
      );
      final backward = mergeSections(
        previous: previous,
        sections: [availability, catalogue],
      );
      expect(backward.fileShas, forward.fileShas);
      expect(backward.deletePaths, forward.deletePaths);
    });

    test('one section gives exactly what mergeSection gives', () {
      final previous = _Previous({'books.json': 'b', 'covers/x.jpg': 'c'});
      final single = mergeSection(previous: previous, section: catalogue);
      final many = mergeSections(previous: previous, sections: [catalogue]);
      expect(many.fileShas, single.fileShas);
      expect(many.deletePaths, single.deletePaths);
      expect(many.files, single.files);
    });

    test('no sections leave the safe record unchanged', () {
      final merge = mergeSections(
        previous: _Previous({'books.json': 'b', '../evil': 'x'}),
        sections: const [],
      );
      expect(merge.fileShas, {'books.json': 'b'});
      expect(merge.deletePaths, isEmpty);
      expect(merge.files, isEmpty);
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

  @override
  bool get catalogueKeyed => false;
}
