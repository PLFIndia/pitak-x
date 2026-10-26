/// Safe message widgets shared by the published-catalogue viewer (network
/// presentation; ADR 0015 V9/V12, viewer plan S4).
///
/// Split out of `published_catalogue_page.dart` for the file-size contract
/// (V16), and for one security reason worth stating: EVERY sentence the viewer
/// shows lives here, so "never print a remote value, a URL, a status code or a
/// raw exception" can be reviewed in one place.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/error/failure.dart';

/// One inline information banner (newer schema, identity conflict).
class PublishedCatalogueBanner extends StatelessWidget {
  /// Creates a banner with an [icon] and a fixed [message].
  const PublishedCatalogueBanner({
    required this.icon,
    required this.message,
    super.key,
  });

  /// The leading icon.
  final IconData icon;

  /// The (locally authored) sentence to show.
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The catalogue-FETCH failure body (the payload itself could not be loaded).
///
/// Distinct from [PublishedCatalogueQueryErrorSliver]: this one has no loaded
/// catalogue behind it, so it replaces the whole body and its Retry re-runs the
/// catalogue request.
class PublishedCatalogueErrorView extends StatelessWidget {
  /// Creates the body for a failed catalogue load.
  const PublishedCatalogueErrorView({
    required this.error,
    required this.onRetry,
    required this.onOpenBrowser,
    super.key,
  });

  /// The typed failure Riverpod surfaced (may be null for an unexpected one).
  final Object? error;

  /// Runs the catalogue Retry action.
  final VoidCallback onRetry;

  /// Opens the saved site in the browser.
  final VoidCallback onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    // Pattern-matched, not a cast: `error` is a field, so it is not promoted.
    final reason = switch (error) {
      PublishedCatalogueFailure(:final reason) => reason,
      _ => null,
    };
    final canRetry = switch (reason) {
      null ||
      PublishedCatalogueFailureReason.disallowedUrl ||
      PublishedCatalogueFailureReason.tooLarge ||
      PublishedCatalogueFailureReason.invalid => false,
      _ => true,
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              messageForCatalogueFailure(reason),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (canRetry)
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                TextButton(
                  onPressed: onOpenBrowser,
                  child: const Text('Open in browser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One plain sentence per typed catalogue failure.
///
/// Never a URL, status code, raw exception, or an unsupported claim such as
/// "not found".
String messageForCatalogueFailure(PublishedCatalogueFailureReason? reason) =>
    switch (reason) {
      PublishedCatalogueFailureReason.httpStatus ||
      PublishedCatalogueFailureReason.redirectRefused ||
      PublishedCatalogueFailureReason.tooManyRedirects =>
        "The site didn't serve this catalogue.",
      PublishedCatalogueFailureReason.timedOut ||
      PublishedCatalogueFailureReason.transport =>
        "Couldn't reach this library. Check your connection and try again.",
      PublishedCatalogueFailureReason.tooLarge =>
        'This catalogue is too large to open in Pitak.',
      PublishedCatalogueFailureReason.invalid =>
        "Pitak couldn't read this published catalogue.",
      PublishedCatalogueFailureReason.disallowedUrl =>
        "This library's address can't be opened in Pitak.",
      null => "Couldn't open this published catalogue.",
    };

/// A result-area message with optional actions (empty, no matches, …).
class PublishedCatalogueMessageSliver extends StatelessWidget {
  /// Creates the message sliver.
  const PublishedCatalogueMessageSliver({
    required this.message,
    this.onOpenBrowser,
    this.onClearFilters,
    super.key,
  });

  /// The locally authored sentence.
  final String message;

  /// Shows "Open in browser" when set.
  final VoidCallback? onOpenBrowser;

  /// Shows "Clear filters" when set.
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onClearFilters != null || onOpenBrowser != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (onClearFilters != null)
                    TextButton(
                      onPressed: onClearFilters,
                      child: const Text('Clear filters'),
                    ),
                  if (onOpenBrowser != null)
                    TextButton(
                      onPressed: onOpenBrowser,
                      child: const Text('Open in browser'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The result area for a failed DERIVED QUERY (filter/sort/group pass).
///
/// Review finding 5: the catalogue loaded fine, but the query worker failed.
/// The page used to treat "no view" as loading and spin forever. This state
/// keeps the header and controls, hides the (stale) rows and count, and offers
/// the one action that can help: re-run the derived query against the loaded
/// catalogue.
///
/// It never shows the isolate exception, its stack trace, the site URL or any
/// remote field value.
class PublishedCatalogueQueryErrorSliver extends StatelessWidget {
  /// Creates the query-failure result area.
  const PublishedCatalogueQueryErrorSliver({required this.onRetry, super.key});

  /// Re-runs only the derived query.
  final VoidCallback onRetry;

  /// The one safe sentence for this state.
  static const String message = "Couldn't display these catalogue results.";

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
