/// Native, read-only view of one saved library's published catalogue
/// (network presentation; ADR 0015, viewer plan S4).
///
/// The screen is driven by three screen-scoped providers keyed by the saved
/// site URL: the catalogue load, the query intent, and (from S5) the cover
/// session. `initState` invalidates them once BEFORE the first watch, so a
/// rapid close/reopen is a new mount with fresh data and a default query
/// intent — never a resurrected stale session (V12).
///
/// The AppBar always carries the explicit **Open in browser** action, on every
/// state. The normal row tap in the saved list opens THIS page and never the
/// browser. Nothing here writes to the local catalogue: the payload belongs to
/// another library and viewing it is not importing it (V2, V15).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_controls.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_list.dart';

/// The viewer screen for one saved [NetworkLibrary] row.
class PublishedCataloguePage extends ConsumerStatefulWidget {
  /// Creates the page. [opener] is the injectable browser seam.
  const PublishedCataloguePage({
    required this.row,
    this.opener = const PublishedSiteOpener(),
    super.key,
  });

  /// The saved row this viewer was opened from (title + conflict badge only).
  final NetworkLibrary row;

  /// The browser hand-off seam (tests inject a recorder).
  final PublishedSiteOpener opener;

  @override
  ConsumerState<PublishedCataloguePage> createState() =>
      _PublishedCataloguePageState();
}

class _PublishedCataloguePageState
    extends ConsumerState<PublishedCataloguePage> {
  late final String _siteUrl = widget.row.siteUrl;
  bool _sessionStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `ref` needs the ProviderScope inherited widget, so this cannot run in
    // `initState`. The first call is the new-session hook: drop anything a
    // winding-down element may still hold, so the first watch fetches exactly
    // once and the query starts at its defaults (V12).
    if (_sessionStarted) return;
    _sessionStarted = true;
    ref
      ..invalidate(publishedCatalogueControllerProvider(_siteUrl))
      ..invalidate(publishedCatalogueQueryControllerProvider(_siteUrl))
      ..invalidate(publishedCatalogueLanguagesProvider(_siteUrl))
      ..invalidate(publishedCatalogueViewProvider(_siteUrl))
      ..invalidate(publishedCatalogueCoverControllerProvider(_siteUrl));
  }

  void _reload() {
    ref.read(publishedCatalogueControllerProvider(_siteUrl).notifier).refresh();
  }

  Future<void> _openBrowser() =>
      openPublishedSiteInBrowser(context, _siteUrl, widget.opener);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publishedCatalogueControllerProvider(_siteUrl));
    final title = widget.row.name.isEmpty
        ? widget.row.siteUrl
        : widget.row.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Reload catalogue',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openBrowser,
          ),
        ],
      ),
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<PublishedCatalogue> state,
  ) {
    // A reload keeps the previous payload on screen with a thin progress bar;
    // a FAILED reload replaces it with the typed error (no stale copy exists).
    if (state.hasValue && !state.hasError) {
      return Column(
        children: [
          if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildCatalogue(context, state.requireValue)),
        ],
      );
    }
    if (state.isLoading) return _loadingBody(context);
    return _errorBody(context, state.error);
  }

  Widget _loadingBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(height: 16),
            Text(
              'Loading this published catalogue…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _openBrowser,
              child: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBody(BuildContext context, Object? error) {
    final reason = error is PublishedCatalogueFailure ? error.reason : null;
    final message = _messageFor(reason);
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (canRetry)
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                TextButton(
                  onPressed: _openBrowser,
                  child: const Text('Open in browser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One plain sentence per typed failure. Never a URL, status code, raw
  /// exception, or an unsupported claim such as "not found".
  static String _messageFor(PublishedCatalogueFailureReason? reason) =>
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

  Widget _buildCatalogue(BuildContext context, PublishedCatalogue catalogue) {
    final viewAsync = ref.watch(publishedCatalogueViewProvider(_siteUrl));
    final languages = ref.watch(publishedCatalogueLanguagesProvider(_siteUrl));
    // `valueOrNull` keeps the previous rows visible while a new engine pass
    // runs, so a keystroke never blanks the list.
    final view = viewAsync.valueOrNull;
    final loadingView = viewAsync.isLoading && view == null;
    final isConflict = widget.row.fetchStatus == FetchStatus.identityConflict;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _headerLine(context, catalogue),
              if (catalogue.hasNewerSchema) ...[
                const SizedBox(height: 8),
                const _Banner(
                  icon: Icons.info_outline,
                  message:
                      'This catalogue was published by a newer Pitak. Some '
                      'details may not be shown. Update Pitak when an update '
                      'is available.',
                ),
              ],
              if (isConflict) ...[
                const SizedBox(height: 8),
                const _Banner(
                  icon: Icons.warning_amber_outlined,
                  message:
                      "This library's published identity has changed since you "
                      'saved it. Nothing was merged or changed here.',
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Availability is the snapshot from publish time, not a live '
                'loan check.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (catalogue.warnings.hasPartialRead) ...[
                const SizedBox(height: 8),
                Text(
                  "Some entries couldn't be displayed.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (catalogue.warnings.hasUnknownKinds) ...[
                const SizedBox(height: 4),
                Text(
                  'Some entries are shown with fewer details.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              PublishedCatalogueControls(
                siteUrl: _siteUrl,
                languages: languages,
              ),
              const SizedBox(height: 8),
              if (view != null)
                Text(
                  '${view.shownItems} of ${view.totalItems} items',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
            ]),
          ),
        ),
        ..._contentSlivers(context, catalogue, view, loadingView),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _contentSlivers(
    BuildContext context,
    PublishedCatalogue catalogue,
    PublishedCatalogueView? view,
    bool loadingView,
  ) {
    // Order matters: rows that were PRESENT but unreadable are a different
    // story from a genuinely empty catalogue (V9/B.2).
    if (catalogue.hasNoReadableItems) {
      return [
        _messageSliver(
          context,
          message: 'No readable items.',
          browserAction: true,
        ),
      ];
    }
    if (catalogue.items.isEmpty) {
      return [
        _messageSliver(
          context,
          message: 'This published catalogue is empty.',
          browserAction: true,
        ),
      ];
    }
    if (loadingView || view == null) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      ];
    }
    if (view.hasNoMatches) {
      return [
        _messageSliver(
          context,
          message: 'No matches.',
          clearAction: () => ref
              .read(
                publishedCatalogueQueryControllerProvider(_siteUrl).notifier,
              )
              .clearFilters(),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: PublishedCatalogueList(view: view, siteUrl: _siteUrl),
      ),
    ];
  }

  Widget _headerLine(BuildContext context, PublishedCatalogue catalogue) {
    final exported = _formatInstant(catalogue.exportedAt);
    return Text(
      exported == null
          ? 'Published catalogue'
          : 'Published catalogue · $exported',
      style: Theme.of(context).textTheme.titleSmall,
    );
  }

  /// A local date for the publish instant, or null when absent.
  static String? _formatInstant(int? millis) {
    if (millis == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Widget _messageSliver(
    BuildContext context, {
    required String message,
    bool browserAction = false,
    VoidCallback? clearAction,
  }) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (clearAction != null)
                TextButton(
                  onPressed: clearAction,
                  child: const Text('Clear filters'),
                ),
              if (browserAction)
                TextButton(
                  onPressed: _openBrowser,
                  child: const Text('Open in browser'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One inline information banner (newer schema, identity conflict).
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message});

  final IconData icon;
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
