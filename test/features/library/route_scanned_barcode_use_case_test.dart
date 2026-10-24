/// `RouteScannedBarcodeUseCase` (plan S13, ADR 0013 D11): a `977` magazine
/// barcode is asked FIRST — it passes the ISBN-13 checksum, so treated as an
/// ISBN it would be stored as a bogus `books.isbn` — and routes by ISSN to
/// an existing title or a new one; everything else takes the ISBN path the
/// S34 quick-add flow already had. A failed read falls through to the
/// "not catalogued yet" route for that barcode kind (navigation, not a
/// security gate — the save paths re-check).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/route_scanned_barcode_use_case.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import '../periodicals/application/periodical_fakes.dart';

/// Item store that answers `findByIsbn` from its rows (`FakeItems` does not
/// implement it — the issue use cases never need it).
class _Items extends FakeItems {
  Failure? findByIsbnFailure;
  final List<String> isbnLookups = [];

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async {
    isbnLookups.add(isbn);
    if (findByIsbnFailure != null) return left(findByIsbnFailure!);
    return right(rows.values.where((b) => b.isbn == isbn).firstOrNull);
  }
}

void main() {
  // 977 + 0317847 (ISSN 0317-8471 without its check) + 00 + EAN check 1.
  const magazineBarcode = '9770317847001';
  const issn = '0317-8471';

  late FakePeriodicals periodicals;
  late _Items items;
  late RouteScannedBarcodeUseCase route;

  setUp(() {
    periodicals = FakePeriodicals();
    items = _Items();
    route = RouteScannedBarcodeUseCase(items: items, periodicals: periodicals);
  });

  group('977 magazine barcodes (D11)', () {
    test('a known ISSN routes to the add-issue flow of that series', () async {
      final series = periodicals.seed(
        const Periodical(title: 'Frontline', issn: issn),
      );

      final decision = await route(magazineBarcode);

      expect(decision, isA<AddIssueOfPeriodical>());
      expect((decision as AddIssueOfPeriodical).periodical.id, series.id);
      expect(periodicals.calls, ['findByIssn:$issn']);
      expect(items.isbnLookups, isEmpty, reason: 'never treated as an ISBN');
    });

    test(
      'a removed ISSN match opens the existing series for restore',
      () async {
        final series = periodicals.seed(
          const Periodical(title: 'Old Weekly', issn: issn, removed: true),
        );

        final decision = await route(magazineBarcode);

        expect(decision, isA<OpenPeriodical>());
        expect((decision as OpenPeriodical).periodical.id, series.id);
        expect(periodicals.calls, ['findByIssn:$issn']);
        expect(items.isbnLookups, isEmpty);
      },
    );

    test(
      'an unknown ISSN offers a new title with the ISSN pre-filled',
      () async {
        final decision = await route(' 977-0317847-001 ');

        expect(decision, isA<AddPeriodicalByIssn>());
        expect((decision as AddPeriodicalByIssn).issn, issn);
        expect(items.isbnLookups, isEmpty);
      },
    );

    test('a failed ISSN read falls through to the new-title route', () async {
      periodicals
        ..seed(const Periodical(title: 'Frontline', issn: issn))
        ..findByIssnFailure = const StorageFailure('disk gone');

      final decision = await route(magazineBarcode);

      expect(decision, isA<AddPeriodicalByIssn>());
    });

    test('a 977 code with a bad check digit is a misread: it takes the ISBN '
        'path unchanged rather than inventing an ISSN', () async {
      final decision = await route('9770317847002');

      expect(decision, isA<AddBookByIsbn>());
      expect((decision as AddBookByIsbn).isbn, '9770317847002');
      expect(periodicals.calls, isEmpty);
    });
  });

  group('ISBN path (S34, unchanged)', () {
    const existing = CatalogueItem(
      id: 7,
      itemUid: 'uid-7',
      title: 'Dune',
      isbn: '9780441172719',
    );

    test('a catalogued ISBN offers the EXISTING item', () async {
      items.rows[existing.id] = existing;

      final decision = await route('978-0-441-17271-9');

      expect(decision, isA<OpenCataloguedItem>());
      expect((decision as OpenCataloguedItem).item.id, 7);
      expect(items.isbnLookups, ['9780441172719'], reason: 'normalised');
      expect(periodicals.calls, isEmpty);
    });

    test('an unknown ISBN opens the add-book form pre-filled', () async {
      final decision = await route('0-14-044913-6');

      expect(decision, isA<AddBookByIsbn>());
      expect((decision as AddBookByIsbn).isbn, '0140449136');
    });

    test('a failed ISBN read falls through to the add-book form', () async {
      items.rows[existing.id] = existing;
      items.findByIsbnFailure = const StorageFailure('disk gone');

      final decision = await route(existing.isbn!);

      expect(decision, isA<AddBookByIsbn>());
    });
  });
}
