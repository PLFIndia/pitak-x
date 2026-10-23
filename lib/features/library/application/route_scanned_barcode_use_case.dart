/// Post-scan barcode routing (application layer, AGENTS.md §3/§4; ADR 0013
/// D11, S34).
///
/// The quick-add scanner returns a string; this use case decides WHERE that
/// string should take the user and returns the decision as a sealed
/// [ScanRoute] value. The page only switches on it — no lookups, no
/// business vocabulary in presentation.
///
/// Why a magazine barcode needs its own branch (beginner note): magazine
/// barcodes are EAN-13 codes with the `977` prefix that carry the title's
/// ISSN, and such a code passes the ISBN-13 checksum. Treated as an ISBN it
/// would be stored as a bogus `books.isbn` and never match the magazine's
/// series. So the 977 case is asked FIRST, before the ISBN path (D11).
///
/// Why a failed read does not fail the route (S34 rule, kept): this is
/// navigation, not a security gate. A repository `Left` falls through to
/// the "not catalogued yet" route for that barcode kind; the add forms
/// re-check on save (ISSN pre-check, D6 identity pre-check, UNIQUE indexes),
/// so a duplicate row stays impossible — fail-safe by layers. The
/// alternative, an error toast that leaves the scan unused, helps nobody.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';

/// Where a scanned barcode should take the user. Sealed so the page's
/// `switch` must handle every destination.
sealed class ScanRoute {
  const ScanRoute();
}

/// The barcode is an ISBN that is already catalogued: offer the EXISTING
/// item instead of an add form the UNIQUE isbn index would refuse at save.
final class OpenCataloguedItem extends ScanRoute {
  /// Creates the route.
  const OpenCataloguedItem(this.item);

  /// The row holding the scanned ISBN.
  final CatalogueItem item;
}

/// The barcode is an ISBN (or any non-magazine code) not yet catalogued:
/// open the add-book form pre-filled with [isbn].
final class AddBookByIsbn extends ScanRoute {
  /// Creates the route.
  const AddBookByIsbn(this.isbn);

  /// The normalised ISBN (dashes/spaces stripped, upper-cased).
  final String isbn;
}

/// The barcode is a magazine code whose ISSN belongs to a catalogued title:
/// open the add-issue form with [periodical] preselected.
final class AddIssueOfPeriodical extends ScanRoute {
  /// Creates the route.
  const AddIssueOfPeriodical(this.periodical);

  /// The series the barcode's ISSN identifies.
  final Periodical periodical;
}

/// The barcode is a magazine code whose ISSN matches no title yet: offer to
/// create a new magazine title with [issn] pre-filled.
final class AddPeriodicalByIssn extends ScanRoute {
  /// Creates the route.
  const AddPeriodicalByIssn(this.issn);

  /// The canonical ISSN (`NNNN-NNNC`) decoded from the barcode.
  final String issn;
}

/// Decides the [ScanRoute] for a raw scanner result.
class RouteScannedBarcodeUseCase {
  /// Creates the use case over the two stores a barcode can match.
  const RouteScannedBarcodeUseCase({
    required CatalogueItemRepository items,
    required PeriodicalRepository periodicals,
  }) : _items = items,
       _periodicals = periodicals;

  final CatalogueItemRepository _items;
  final PeriodicalRepository _periodicals;

  /// Routes [raw] (the scanner's string, dashes/spaces tolerated).
  ///
  /// A valid `977…` EAN-13 is a magazine barcode: its ISSN is looked up and
  /// the route is [AddIssueOfPeriodical] or [AddPeriodicalByIssn]. Anything
  /// else takes the ISBN path exactly as before this use case existed —
  /// normalised, looked up, [OpenCataloguedItem] or [AddBookByIsbn]. A
  /// `977` code with a bad check digit is a misread; it is not an ISBN
  /// either, but it falls through to the ISBN path so the user still sees
  /// the digits in the form rather than nothing (unchanged behaviour).
  Future<ScanRoute> call(String raw) async {
    final issn = Issn.fromEan13(raw);
    if (issn != null) return _routeIssn(issn);
    return _routeIsbn(IsbnFormat.normalize(raw));
  }

  Future<ScanRoute> _routeIssn(String issn) async {
    final existing = await _periodicals.findByIssn(issn);
    final periodical = existing.getOrElse((_) => null);
    return periodical == null
        ? AddPeriodicalByIssn(issn)
        : AddIssueOfPeriodical(periodical);
  }

  Future<ScanRoute> _routeIsbn(String isbn) async {
    final existing = await _items.findByIsbn(isbn);
    final item = existing.getOrElse((_) => null);
    return item == null ? AddBookByIsbn(isbn) : OpenCataloguedItem(item);
  }
}
