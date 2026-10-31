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
