import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

import 'bundle_test_fixture.dart';
import 's11_interchange_roundtrip_fixture.dart';

/// Magazine remediation S5: a v4 bundle must round-trip its series, their
/// issues and their cover bytes. Every test here uses the REAL reader, the
/// REAL validator and a REAL in-memory Drift database — a fake would happily
/// hide the "periodicals silently dropped" bug this session exists to fix.
Uint8List _zip(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach(
    (name, data) => archive.addFile(ArchiveFile(name, data.length, data)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// A v4 document: one title, one issue of it, both naming the same cover leaf.
String _sharedCoverJson({String notes = 'x'}) => jsonEncode({
  'schemaVersion': 4,
  'periodicals': [
    {
      'periodicalUid': 'p-shared',
      'title': 'Frontline',
      'publisher': 'The Hindu Group',
      'coverUrl': 'covers/shared.jpg',
    },
  ],
  'books': [
    {
      'bookUid': 'issue-1',
      'title': 'Whatever the file says',
      'kind': 'magazine-issue',
      'coverUrl': 'covers/shared.jpg',
      'notes': notes,
      'issue': {'periodicalUid': 'p-shared', 'volume': 1, 'issueNumber': 7},
    },
  ],
});

void main() {
  late BundleTestFixture fixture;
  setUp(() => fixture = BundleTestFixture());
  tearDown(() async => fixture.dispose());

  test(
    'a real v4 ZIP persists the series, its issue and one shared cover',
    () async {
      // A field past the cap proves the parser's warnings survive validation
      // (S5 made validate() lossless) and reach the summary.
      final longNotes = 'x' * (CatalogueRules.maxFieldChars + 5);
      final bytes = _zip({
        'library.json': utf8.encode(_sharedCoverJson(notes: longNotes)),
        'cover_shared.jpg': [1, 2, 3],
      });

      final bundle = (await const LibraryBundleReader().read(
        bytes,
      )).getOrElse((f) => fail('reader refused a valid v4 bundle: $f'));

      final summary = (await fixture.apply(
        bundle.payload,
        images: bundle.covers,
      )).getOrElse((f) => fail('import refused: $f'));

      expect(summary.periodicalsAdded, 1);
      expect(summary.booksAdded, 1);
      expect(summary.warnings, isNotEmpty);
      expect(summary.warnings.join(' '), contains('shortened'));

      final series = (await fixture.periodicals.listAll())
          .getOrElse((f) => fail('series read failed: $f'))
          .single
          .periodical;
      expect(series.title, 'Frontline');
      expect(series.coverUrl, startsWith('covers/'));
      expect(fixture.cover(series.coverUrl!).existsSync(), isTrue);

      final issue = (await fixture.books.getAll())
          .getOrElse((f) => fail('item read failed: $f'))
          .single;
      expect(issue.kind, ItemKind.magazineIssue);
      expect(issue.issue?.periodicalUid, 'p-shared');
      expect(issue.issue?.issueNumber, 7);
      // Re-projected from the series, not the file's own title.
      expect(issue.title, 'Frontline — Vol 1 No 7');
      // The series and the issue named ONE source leaf: it was staged once.
      expect(fixture.images, hasLength(1));
    },
  );

  test(
    'a periodicals-only v4 bundle imports its titles, not nothing',
    () async {
      final bytes = _zip({
        'library.json': utf8.encode(
          '{"schemaVersion":4,"periodicals":['
          '{"periodicalUid":"p-only","title":"Only Title"}]}',
        ),
      });
      final bundle = (await const LibraryBundleReader().read(
        bytes,
      )).getOrElse((f) => fail('reader refused a titles-only bundle: $f'));

      final summary = (await fixture.apply(
        bundle.payload,
        images: bundle.covers,
      )).getOrElse((f) => fail('import refused: $f'));

      expect(summary.periodicalsAdded, 1);
      expect(summary.booksAdded, 0);
      expect(
        (await fixture.periodicals.listAll()).getOrElse(
          (f) => fail('series read failed: $f'),
        ),
        hasLength(1),
      );
    },
  );

  test('an unsafe or missing series cover fails before any write', () async {
    Future<Object?> refuse(List<int> seriesCover, String? coverEntry) async {
      final json = jsonEncode({
        'schemaVersion': 4,
        'periodicals': [
          {
            'periodicalUid': 'p1',
            'title': 'Frontline',
            'coverUrl': utf8.decode(seriesCover),
          },
        ],
      });
      final entries = <String, List<int>>{'library.json': utf8.encode(json)};
      if (coverEntry != null) entries[coverEntry] = [1];
      final result = await const LibraryBundleReader().read(_zip(entries));
      return result.swap().toNullable();
    }

    // Missing leaf, unsafe leaf, and an unreferenced extra cover.
    expect(
      await refuse(utf8.encode('covers/missing.jpg'), null),
      isA<BackupCorruptFailure>(),
    );
    expect(
      await refuse(utf8.encode('covers/../escape.jpg'), null),
      isA<BackupCorruptFailure>(),
    );
    expect(
      await refuse(utf8.encode('covers/ok.jpg'), 'cover_other.jpg'),
      isA<BackupCorruptFailure>(),
    );

    // Nothing reached the database or the covers directory.
    expect(
      (await fixture.periodicals.listAll()).getOrElse(
        (f) => fail('series read failed: $f'),
      ),
      isEmpty,
    );
    expect(fixture.images, isEmpty);
  });

  test('a failed import removes only the series covers it staged', () async {
    // A photo already on this device: rollback must never touch it.
    final existing = File('${fixture.directory.path}/existing.jpg')
      ..writeAsBytesSync([9, 9, 9]);
    (await fixture.books.insert(
      const CatalogueItem(
        title: 'Already here',
        itemUid: 'shared-uid',
        coverUrl: 'covers/existing.jpg',
      ),
    )).getOrElse((f) => fail('seed failed: $f'));

    final bytes = _zip({
      'library.json': utf8.encode(
        jsonEncode({
          'schemaVersion': 4,
          'periodicals': [
            {
              'periodicalUid': 'p1',
              'title': 'Frontline',
              'coverUrl': 'covers/new.jpg',
            },
          ],
          // Same UID as a stored BOOK: the cross-kind refusal lands AFTER the
          // series pass, which is exactly the rollback path under test.
          'books': [
            {
              'bookUid': 'shared-uid',
              'title': 'Trying to become an issue',
              'kind': 'magazine-issue',
              'issue': {'periodicalUid': 'p1', 'issueNumber': 1},
            },
          ],
        }),
      ),
      'cover_new.jpg': [1, 2, 3],
    });
    final bundle = (await const LibraryBundleReader().read(
      bytes,
    )).getOrElse((f) => fail('reader refused: $f'));

    final result = await fixture.apply(bundle.payload, images: bundle.covers);
    expect(result.swap().toNullable(), isA<ValidationFailure>());

    // Series and item rolled back; the staged series cover was deleted.
    expect(
      (await fixture.periodicals.listAll()).getOrElse(
        (f) => fail('series read failed: $f'),
      ),
      isEmpty,
    );
    expect(
      (await fixture.books.getAll()).getOrElse(
        (f) => fail('item read failed: $f'),
      ),
      hasLength(1),
    );
    expect(fixture.images.map((f) => f.uri.pathSegments.last), [
      'existing.jpg',
    ]);
    expect(existing.existsSync(), isTrue);
  });

  test('an issue row whose series is missing becomes a plain book', () async {
    final bytes = _zip({
      'library.json': utf8.encode(
        jsonEncode({
          'schemaVersion': 4,
          'books': [
            {
              'bookUid': 'orphan',
              'title': 'Orphan Issue',
              'kind': 'magazine-issue',
              'issue': {'periodicalUid': 'nope', 'issueNumber': 3},
            },
          ],
        }),
      ),
    });
    final bundle = (await const LibraryBundleReader().read(
      bytes,
    )).getOrElse((f) => fail('reader refused: $f'));
    final summary = (await fixture.apply(
      bundle.payload,
      images: bundle.covers,
    )).getOrElse((f) => fail('import refused: $f'));

    expect(summary.booksAdded, 1);
    final row = (await fixture.books.getAll())
        .getOrElse((f) => fail('item read failed: $f'))
        .single;
    expect(row.kind, ItemKind.book);
    expect(row.details, isNot(isA<IssueOf>()));
  });

  test(
    'S11 v4 ZIP round-trips the complete matrix and cover ownership',
    () async {
      final source = BundleTestFixture();
      addTearDown(source.dispose);
      await seedS11InterchangeSource(source);
      final exported = await exportS11InterchangeJson(source);
      expect(
        (jsonDecode(exported) as Map<String, dynamic>)['schemaVersion'],
        4,
      );

      final bytes = _zip({
        'library.json': utf8.encode(padS11LegacyIdentities(exported)),
        s11LocalSeriesCoverEntry: s11LocalSeriesCoverBytes,
      });
      final bundle = (await const LibraryBundleReader().read(
        bytes,
      )).getOrElse((failure) => fail('reader refused the v4 ZIP: $failure'));
      final summary = (await fixture.apply(
        bundle.payload,
        images: bundle.covers,
      )).getOrElse((failure) => fail('ZIP import failed: $failure'));
      expect(summary.parseErrors, isEmpty);
      expect(summary.periodicalsAdded, 2);
      expect(summary.booksAdded, 4);

      await expectS11InterchangeState(fixture, localCoverPreserved: true);
    },
  );
}
