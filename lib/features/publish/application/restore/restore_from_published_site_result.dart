/// User-facing outcomes of a restore from the active published site.
library;

import 'package:pitaka/features/import_export/application/import_library_use_case.dart';

/// Terminal restore outcome.
sealed class RestoreFromPublishedSiteOutcome {
  /// Creates an outcome.
  const RestoreFromPublishedSiteOutcome();
}

/// Cancellation before any database write.
final class RestoreFromPublishedSiteCancelled
    extends RestoreFromPublishedSiteOutcome {
  /// Creates the cancelled outcome.
  const RestoreFromPublishedSiteCancelled();
}

/// A committed catalogue plus its honest loss/identity report.
final class RestoreFromPublishedSiteSuccess
    extends RestoreFromPublishedSiteOutcome {
  /// Creates a success outcome.
  const RestoreFromPublishedSiteSuccess(this.summary);

  /// What was restored, skipped, dropped, or left pending.
  final RestoreFromPublishedSiteSummary summary;
}

/// Structured restore counts and identity state.
final class RestoreFromPublishedSiteSummary {
  /// Creates a summary.
  const RestoreFromPublishedSiteSummary({
    required this.import,
    required this.rowsDropped,
    required this.droppedFields,
    required this.issuesFiledAsBooks,
    required this.coversRestored,
    required this.coversSkipped,
    required this.coversSkippedByBudget,
    required this.thirdPartyCoverLinks,
    required this.downloadCovers,
    required this.identityMissing,
    required this.identityPending,
  });

  /// Importer counts, including duplicate skips and warnings.
  final ImportSummary import;

  /// Rows dropped by the reader or validation gates.
  final int rowsDropped;

  /// Optional fields dropped by the defensive reader.
  final int droppedFields;

  /// Issues degraded because their series was absent.
  final int issuesFiledAsBooks;

  /// Distinct same-site cover files restored.
  final int coversRestored;

  /// Distinct same-site cover references left empty.
  final int coversSkipped;

  /// Subset of [coversSkipped] caused by a safety budget.
  final int coversSkippedByBudget;

  /// Distinct third-party links retained but not fetched.
  final int thirdPartyCoverLinks;

  /// Whether same-site cover download was consented to.
  final bool downloadCovers;

  /// No usable `library.json` was present, so the derived identity is used.
  final bool identityMissing;

  /// The catalogue committed but identity recovery still needs to finish.
  final bool identityPending;

  /// Catalogue items inserted (fresh item UUIDs).
  int get itemsAdded => import.booksAdded;

  /// Magazine titles inserted (published series UIDs preserved).
  int get periodicalsAdded => import.periodicalsAdded;

  /// Changes only identity-pending state after a successful retry.
  RestoreFromPublishedSiteSummary copyWith({bool? identityPending}) =>
      RestoreFromPublishedSiteSummary(
        import: import,
        rowsDropped: rowsDropped,
        droppedFields: droppedFields,
        issuesFiledAsBooks: issuesFiledAsBooks,
        coversRestored: coversRestored,
        coversSkipped: coversSkipped,
        coversSkippedByBudget: coversSkippedByBudget,
        thirdPartyCoverLinks: thirdPartyCoverLinks,
        downloadCovers: downloadCovers,
        identityMissing: identityMissing,
        identityPending: identityPending ?? this.identityPending,
      );
}
