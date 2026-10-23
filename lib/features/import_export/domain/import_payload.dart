/// Result of parsing an import file (AGENTS.md §3.1, pure Dart).
///
/// Mirror of Kotlin `ImportPayload`: parsed rows plus a list of per-row parse
/// errors. Importers MUST NOT throw on a malformed row — they collect a
/// human-readable error so the user sees a count of what could and couldn't be
/// ingested (Kotlin D26: no terminal dead-ends).
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Parsed, not-yet-persisted catalogue items + wishlist entries from an
/// import file.
class ImportPayload {
  /// Creates an import payload.
  const ImportPayload({
    this.items = const [],
    this.periodicals = const [],
    this.wishlist = const [],
    this.parseErrors = const [],
    this.warnings = const [],
  });

  /// Catalogue items to import (ids not yet assigned). The Pitaka-JSON key
  /// that feeds this list stays `books` (wire contract, ADR 0014). An item
  /// may carry `details` (an issue's `IssueOf`, an other's `OtherItemOf`
  /// marker) — kinds ride the same list (F5).
  final List<CatalogueItem> items;

  /// Magazine titles to import (ids not yet assigned; ADR 0014 W1). A v4
  /// document carries them top-level as `periodicals[]`; they are applied
  /// BEFORE [items] so issues meet their series already in place.
  final List<Periodical> periodicals;

  /// Wishlist entries to import (ids not yet assigned).
  final List<WishlistBook> wishlist;

  /// Per-row / file-level parse errors, safe to surface to the user. A row
  /// named here was SKIPPED (M15: invalid values are rejected, not coerced).
  final List<String> parseErrors;

  /// Non-fatal adjustments applied to KEPT rows (M15, D2 = truncate + report):
  /// an over-long text field was shortened, or a disallowed cover link was
  /// dropped. Separate from [parseErrors] because `ImportBundle.validate`
  /// refuses a bundle with ANY parse error — a warning must not sink a
  /// bundle.
  final List<String> warnings;

  /// True when nothing parseable was found.
  bool get isEmpty => items.isEmpty && periodicals.isEmpty && wishlist.isEmpty;
}

/// Common interface for every import-file reader (Kotlin `Importer`).
//
// Single-method, but kept as an interface so the sniffer and use cases can
// depend on the abstraction across the JSON/CSV/bundle implementations.
// ignore: one_member_abstracts
abstract interface class Importer {
  /// Parses [text] into an [ImportPayload]. Implementations must not throw on
  /// malformed rows — collect per-row errors into [ImportPayload.parseErrors].
  ImportPayload parse(String text);
}
