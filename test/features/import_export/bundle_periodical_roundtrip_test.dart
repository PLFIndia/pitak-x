import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'bundle_test_fixture.dart';

/// Magazine remediation S5: an import of rows WITH their cover pictures
/// (`importBundle`) must carry the series, their issues and their cover
/// bytes. Every test here uses the REAL validator and a REAL in-memory Drift
/// database — a fake would happily hide the "periodicals silently dropped"
/// bug that session fixed.
///
/// The rows are built here, as the restore from the user's own published
/// site hands them over. Until BR7 they came out of a bundle file; reading
/// such a file was removed (decision D29), and with it the tests of that
/// reader. What a JSON file does with the same rows is tested in
/// `pitaka_json_importer_test.dart` and `export_roundtrip_test.dart`.
void main() {
  late BundleTestFixture fixture;
  setUp(() => fixture = BundleTestFixture());
  tearDown(() async => fixture.dispose());

  test('a series, its issue and one shared cover are stored; the cover is '
      'stored once', () async {
    // A warning proves that what the parser noted survives validation (S5
    // made `ImportBundle.validate` lossless) and reaches the summary.
    const warning = 'Book "Whatever the source says" (row 1): notes shortened.';
    final summary = (await fixture.apply(
      const ImportPayload(
        periodicals: [
          Periodical(
            periodicalUid: 'p-shared',
            title: 'Frontline',
            publisher: 'The Hindu Group',
            coverUrl: 'covers/shared.jpg',
          ),
        ],
        items: [
          CatalogueItem(
            itemUid: 'issue-1',
            title: 'Whatever the source says',
            coverUrl: 'covers/shared.jpg',
            notes: 'x',
            details: IssueOf(
              periodicalUid: 'p-shared',
              volume: 1,
              issueNumber: 7,
            ),
          ),
        ],
        warnings: [warning],
      ),
      images: {
        'shared.jpg': Uint8List.fromList([1, 2, 3]),
      },
    )).getOrElse((f) => fail('import refused: $f'));

    expect(summary.periodicalsAdded, 1);
    expect(summary.booksAdded, 1);
    expect(summary.warnings, [warning]);

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
    // Re-projected from the series, not the row's own title.
    expect(issue.title, 'Frontline — Vol 1 No 7');
    // The series and the issue named ONE source leaf: it was staged once.
    expect(fixture.images, hasLength(1));
  });

  test('magazine titles alone are imported, not nothing', () async {
    final summary = (await fixture.apply(
      const ImportPayload(
        periodicals: [Periodical(periodicalUid: 'p-only', title: 'Only Title')],
      ),
    )).getOrElse((f) => fail('import refused: $f'));

    expect(summary.periodicalsAdded, 1);
    expect(summary.booksAdded, 0);
    expect(
      (await fixture.periodicals.listAll()).getOrElse(
        (f) => fail('series read failed: $f'),
      ),
      hasLength(1),
    );
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

    final result = await fixture.apply(
      const ImportPayload(
        periodicals: [
          Periodical(
            periodicalUid: 'p1',
            title: 'Frontline',
            coverUrl: 'covers/new.jpg',
          ),
        ],
        // Same UID as a stored BOOK: the cross-kind refusal lands AFTER the
        // series pass, which is exactly the rollback path under test.
        items: [
          CatalogueItem(
            itemUid: 'shared-uid',
            title: 'Trying to become an issue',
            details: IssueOf(periodicalUid: 'p1', issueNumber: 1),
          ),
        ],
      ),
      images: {
        'new.jpg': Uint8List.fromList([1, 2, 3]),
      },
    );
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
}
