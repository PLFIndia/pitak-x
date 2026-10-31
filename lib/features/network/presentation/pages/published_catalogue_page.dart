/// Native, read-only view of one saved library's published catalogue
/// (network presentation; ADR 0015, viewer plan S4).
///
/// The screen is driven by three screen-scoped providers keyed by the saved
/// site URL: the catalogue load, the query intent, and (from S5) the cover
/// session. `initState` invalidates them once BEFORE the first watch, so a
/// rapid close/reopen is a new mount with fresh data and a default query
/// intent — never a resurrected stale session (V12).
///
/// When the library cannot be checked, the page shows the device's saved copy
/// under a banner that says how old it is and why (ADR 0018); it never passes
/// a saved copy off as current.
///
/// The AppBar always carries the explicit **Open in browser** action, on every
/// state. The normal row tap in the saved list opens THIS page and never the
/// browser. Nothing here writes to the local catalogue: the payload belongs to
/// another library and viewing it is not importing it (V2, V15).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_controller.dart';
import 'package:pitaka/features/network/application/published_events_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_controls.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_list.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_messages.dart';
import 'package:pitaka/features/network/presentation/widgets/published_cover_consent_banner.dart';
import 'package:pitaka/features/network/presentation/widgets/published_cover_image_cache_cleanup.dart';
import 'package:pitaka/features/network/presentation/widgets/published_events_section.dart';

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

  /// Owns the Flutter-global image-cache cleanup for this whole route.
  PublishedCoverImageCacheCleanup? _coverCleanup;

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
      ..invalidate(publishedCatalogueCoverControllerProvider(_siteUrl))
      ..invalidate(publishedEventsControllerProvider(_siteUrl));
    // After the invalidation, so the subscription follows the NEW cover
    // session. Presentation owns the global cache cleanup because the
    // application layer must never import Flutter's painting APIs.
    _coverCleanup = PublishedCoverImageCacheCleanup.attach(
      ref: ref,
      siteUrl: _siteUrl,
    );
  }

  @override
  void dispose() {
    // Evict this session's images before the element goes away: the Riverpod
    // controller only clears its own byte maps.
    _coverCleanup?.dispose();
    _coverCleanup = null;
    super.dispose();
  }

  void _reload() {
    final catalogue = ref.read(
      publishedCatalogueControllerProvider(_siteUrl).notifier,
    );
    // ONE decision drives both halves of a reload. Asking the catalogue
    // controller first means an ignored tap — during the initial load, or while
    // a reload is already running — cannot clear the covers of the payload that
    // is still on screen (review finding 2).
    if (!catalogue.canRefresh) return;
    // Deliberately no `await` between the check, the reset and the refresh:
    // this whole sequence runs on the single UI isolate, so a second tap in the
    // same frame cannot see a stale `canRefresh` and reset a second time.
    ref
        .read(publishedCatalogueCoverControllerProvider(_siteUrl).notifier)
        .reset();
    // Events publish independently, so Reload refreshes their sibling file in
    // the same deliberate action. Each controller still owns its own revision
    // and duplicate-request guard.
    ref.read(publishedEventsControllerProvider(_siteUrl).notifier).refresh();
    // The new generation starts empty; the rows stay visible with placeholders
    // and are PAUSED (below) until this load publishes the new payload, so no
    // cover of the old payload is requested while the GET is in flight.
    catalogue.refresh();
  }

  Future<void> _openBrowser() =>
      openPublishedSiteInBrowser(context, _siteUrl, widget.opener);

  /// Re-runs ONLY the derived query, against the catalogue already in memory.
  ///
  /// Deliberately not `refresh()`: the payload loaded fine. The narrowing also
  /// keeps the user's query intent, the cover session, the facet list and the
  /// viewer's HTTP client untouched (review finding 5).
  void _retryQuery() =>
      ref.invalidate(publishedCatalogueViewProvider(_siteUrl));

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
    AsyncValue<PublishedContent<PublishedCatalogue>> state,
  ) {
    // A reload keeps the previous payload on screen with a thin progress bar.
    // A failed reload that still had a saved copy arrives as DATA (the saved
    // copy plus its notice); only a failure with no saved copy is an error,
    // and it replaces the payload with the typed message.
    if (state.hasValue && !state.hasError) {
      return Column(
        children: [
          if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _buildCatalogue(
              context,
              state.requireValue,
              // While an accepted reload runs, the rows on screen belong to the
              // OLD payload: they may keep painting, but they must not start
              // cover requests for it (review finding 2, step 5).
              coverRequestsPaused: state.isLoading,
            ),
          ),
        ],
      );
    }
    if (state.isLoading) return _loadingBody(context);
    return _errorBody(state.error);
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

  Widget _errorBody(Object? error) => PublishedCatalogueErrorView(
    error: error,
    onRetry: _reload,
    onOpenBrowser: _openBrowser,
  );

  Widget _buildCatalogue(
    BuildContext context,
    PublishedContent<PublishedCatalogue> content, {
    required bool coverRequestsPaused,
  }) {
    final catalogue = content.value;
    final savedCopy = content.savedCopy;
    final viewAsync = ref.watch(publishedCatalogueViewProvider(_siteUrl));
    final languages = ref.watch(publishedCatalogueLanguagesProvider(_siteUrl));
    // `valueOrNull` keeps the previous rows visible while a new engine pass
    // runs, so a keystroke never blanks the list — but a FAILURE must never be
    // hidden behind those stale rows, so `hasError` is read explicitly
    // (review finding 5).
    final queryFailed = viewAsync.hasError;
    final view = viewAsync.valueOrNull;
    final loadingView = viewAsync.isLoading && view == null && !queryFailed;
    final isConflict = widget.row.fetchStatus == FetchStatus.identityConflict;
    // Watching here starts the optional events load alongside the catalogue
    // header and also lets the image-consent prompt account for poster-only
    // sites. The section itself watches the full state for rendering/retry.
    final hasEventPosters = ref.watch(
      publishedEventsControllerProvider(
        _siteUrl,
      ).select((s) => s.valueOrNull?.value.posters.isNotEmpty ?? false),
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _headerLine(context, catalogue),
              if (savedCopy != null) ...[
                const SizedBox(height: 8),
                PublishedCatalogueBanner(
                  icon: Icons.history,
                  message: savedCopyMessage(savedCopy),
                ),
              ],
              if (catalogue.hasNewerSchema) ...[
                const SizedBox(height: 8),
                const PublishedCatalogueBanner(
                  icon: Icons.info_outline,
                  message:
                      'This catalogue was published by a newer Pitak. Some '
                      'details may not be shown. Update Pitak when an update '
                      'is available.',
                ),
              ],
              if (isConflict) ...[
                const SizedBox(height: 8),
                const PublishedCatalogueBanner(
                  icon: Icons.warning_amber_outlined,
                  message:
                      "This library's published identity has changed since you "
                      'saved it. Nothing was merged or changed here.',
                ),
              ],
              PublishedCoverConsentBanner(
                catalogue: catalogue,
                hasEventPosters: hasEventPosters,
              ),
              PublishedEventsSection(
                siteUrl: _siteUrl,
                coverRequestsPaused: coverRequestsPaused,
              ),
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
              if (view != null && !queryFailed)
                Text(
                  '${view.shownItems} of ${view.totalItems} items',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
            ]),
          ),
        ),
        ..._contentSlivers(
          catalogue,
          view,
          loadingView,
          queryFailed: queryFailed,
          coverRequestsPaused: coverRequestsPaused,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _contentSlivers(
    PublishedCatalogue catalogue,
    PublishedCatalogueView? view,
    bool loadingView, {
    required bool queryFailed,
    required bool coverRequestsPaused,
  }) {
    // A failed query outranks every other result message: the empty/no-match
    // wording would be a claim the app cannot make when the pass never
    // finished. The header and controls stay available above it.
    if (queryFailed) {
      return [PublishedCatalogueQueryErrorSliver(onRetry: _retryQuery)];
    }
    // Order matters: rows that were PRESENT but unreadable are a different
    // story from a genuinely empty catalogue (V9/B.2).
    if (catalogue.hasNoReadableItems) {
      return [
        PublishedCatalogueMessageSliver(
          message: 'No readable items.',
          onOpenBrowser: _openBrowser,
        ),
      ];
    }
    if (catalogue.items.isEmpty) {
      return [
        PublishedCatalogueMessageSliver(
          message: 'This published catalogue is empty.',
          onOpenBrowser: _openBrowser,
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
        PublishedCatalogueMessageSliver(
          message: 'No matches.',
          onClearFilters: () => ref
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
        sliver: PublishedCatalogueList(
          view: view,
          siteUrl: _siteUrl,
          coverRequestsPaused: coverRequestsPaused,
        ),
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
}
