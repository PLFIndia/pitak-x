/// The series detail screen — one magazine title, its subscription state and
/// its issues (periodicals presentation layer, AGENTS.md §3.1; ADR 0013 U2).
///
/// **Observes the series by id (N03).** The page is pushed with a
/// `periodicalId` (and, optionally, the list row's entity so the first frame
/// is not a spinner) and watches `periodicalByIdProvider` from then on —
/// exactly the contract of the book detail page. A row that vanished shows a
/// safe empty state; a repository failure shows a safe message, never raw
/// text.
///
/// The issues are the catalogue narrowed to this series' uid
/// ([IssueListController], a paged read newest-first), rendered with the
/// SAME list/paging idiom as the Library screen: one outer scroll view, the
/// next page requested as the user nears the end, a footer spinner while it
/// is in flight.
///
/// A REMOVED title is visible but actionless (D8): the edit and "+ Add
/// issue" entries hide, and the add-issue use case is the authoritative guard
/// against a new write. Historical issue edits remain allowed. The overflow
/// offers Remove / Restore (soft, no confirmation needed to restore) and the
/// hard delete, whose typed
/// refusal ("still has N issues") is the guard — delete the issues first, or
/// remove the title instead.
///
/// Edit opens the series form prefilled with the observed row; "+ Add issue"
/// opens the issue form with this series preselected (both S16).
///
/// The subscription card, the overflow menu and the removed badge live in
/// `widgets/periodical_detail_sections.dart` (the page grew over the
/// file-size cap; same split as S14's `catalogue_item_actions.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/pages/catalogue_item_detail_page.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_row.dart';
import 'package:pitaka/features/periodicals/application/issue_list_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/periodical_detail_sections.dart';

/// How close to the end (in logical pixels of remaining scroll extent) the
/// next issues page is requested — same rule as the Library screen.
const double _loadMoreThreshold = 600;

/// Key of the footer indicator shown while the next issues page is in flight
/// (tests locate it by this key).
const periodicalLoadMoreKey = ValueKey('periodical-load-more');

/// Displays the magazine title with id [periodicalId], kept current.
class PeriodicalDetailPage extends ConsumerWidget {
  /// Creates the detail page for the series with [periodicalId].
  /// [initialPeriodical] is the row the caller already has (the tapped list
  /// row); it is shown only until the observed row arrives.
  const PeriodicalDetailPage({
    required this.periodicalId,
    this.initialPeriodical,
    super.key,
  });

  /// Per-device id of the series to observe.
  final int periodicalId;

  /// Optional snapshot for the first frame; never used once the provider has
  /// resolved, and never handed to any action.
  final Periodical? initialPeriodical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final observed = ref.watch(periodicalByIdProvider(periodicalId));
    // `valueOrNull` keeps the previous value during a reload, so a rewritten
    // row swaps in without a loading flash; `hasValue` distinguishes
    // "resolved to null" (the series is gone) from "not resolved yet".
    if (observed.hasValue) {
      final periodical = observed.valueOrNull;
      if (periodical == null) return const _SeriesGoneScaffold();
      return _SeriesDetailBody(periodical: periodical);
    }
    if (observed.hasError) return const _SeriesLoadFailedScaffold();
    final first = initialPeriodical;
    if (first != null && first.id == periodicalId) {
      return _SeriesDetailBody(periodical: first);
    }
    return const Scaffold(
      appBar: _DetailAppBar(),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// The plain "Magazine" app bar shared by the loading / gone / failed
/// states.
class _DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('Magazine'));
}

/// Shown when the observed series no longer exists (deleted while this page
/// was open). No actions: there is nothing to edit or delete.
class _SeriesGoneScaffold extends StatelessWidget {
  const _SeriesGoneScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _DetailAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This magazine title is no longer in your library.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Shown when the series could not be read. Plain-language only (AGENTS.md
/// §5: never raw exception text).
class _SeriesLoadFailedScaffold extends StatelessWidget {
  const _SeriesLoadFailedScaffold();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const _DetailAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't load this magazine title. Please go back and try again.",
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: scheme.error),
          ),
        ),
      ),
    );
  }
}

/// The detail screen proper, rendered for the CURRENT [periodical]. Every
/// action here uses this observed row — never a captured snapshot (N03).
class _SeriesDetailBody extends ConsumerWidget {
  const _SeriesDetailBody({required this.periodical});

  final Periodical periodical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final uid = periodical.periodicalUid;
    // A persisted series always has a uid (minted at insert); null means the
    // first-frame snapshot of a broken caller — render no issues rather than
    // query for a blank key (fail closed).
    final issuesAsync = uid == null
        ? null
        : ref.watch(issueListControllerProvider(uid));
    final issues = issuesAsync?.valueOrNull;

    // Paging: ask for the next window near the end of the ONE outer scroll
    // view (the header and the issue rows share it). The controller
    // de-duplicates concurrent calls, so firing on every notification is
    // cheap and safe.
    bool onScroll(ScrollNotification notification) {
      final window = issues;
      if (uid != null &&
          window != null &&
          window.hasMore &&
          !window.isLoadingMore &&
          notification.metrics.extentAfter < _loadMoreThreshold) {
        ref.read(issueListControllerProvider(uid).notifier).loadMore();
      }
      return false; // let the notification keep bubbling
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Magazine'),
        actions: [
          if (!periodical.removed)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
              // The series form, pre-filled with the CURRENT row (N03: the
              // form re-reads it again at save time).
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PeriodicalFormPage(periodical: periodical),
                ),
              ),
            ),
          SeriesOverflowMenu(periodical: periodical),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: onScroll,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      // Keyed on the cover ref so a new capture forces an
                      // image reload (same rule as the book detail page).
                      child: ItemCover(
                        key: ValueKey(periodical.coverUrl),
                        title: periodical.title,
                        coverUrl: periodical.coverUrl,
                        owner: periodical.periodicalUid == null
                            ? null
                            : CoverOwners.periodical(periodical.periodicalUid!),
                        width: 120,
                        height: 168,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(periodical.title, style: textTheme.headlineSmall),
                    if (_has(periodical.titleTransliteration)) ...[
                      const SizedBox(height: 4),
                      Text(
                        periodical.titleTransliteration!,
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_has(periodical.publisher)) ...[
                      const SizedBox(height: 4),
                      Text(periodical.publisher!, style: textTheme.titleMedium),
                    ],
                    if (periodical.removed) ...[
                      const SizedBox(height: 12),
                      const SeriesRemovedBadge(),
                    ],
                    if (periodical.isSubscriptionTracked ||
                        periodical.frequency != null) ...[
                      const SizedBox(height: 16),
                      // The injected clock (N04), not DateTime.now: tests pin
                      // it, and the tick re-reads the observed series, so the
                      // badge rolls over while the page stays open.
                      SeriesSubscriptionCard(
                        periodical: periodical,
                        now: DateTime.fromMillisecondsSinceEpoch(
                          ref.watch(clockProvider)(),
                        ),
                      ),
                    ],
                    if (!periodical.removed) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        // The add-issue form, preselected with THIS series.
                        onPressed: uid == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      AddIssuePage(periodical: periodical),
                                ),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add issue'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Issues',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            ..._issueSlivers(context, ref, uid, issuesAsync),
          ],
        ),
      ),
    );
  }

  static bool _has(String? v) => v != null && v.trim().isNotEmpty;

  /// The slivers for the issues section: the paged rows, the empty/loading/
  /// error states, and the footer spinner while the next page is in flight.
  List<Widget> _issueSlivers(
    BuildContext context,
    WidgetRef ref,
    String? uid,
    AsyncValue<LibraryWindow>? issuesAsync,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final window = issuesAsync?.valueOrNull;
    if (window != null) {
      if (window.books.isEmpty) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'No issues catalogued yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ];
      }
      void openDetail(CatalogueItem issue) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CatalogueItemDetailPage(bookId: issue.id, initialBook: issue),
        ),
      );
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: window.books.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final issue = window.books[index];
              return CatalogueItemRow(
                book: issue,
                onTap: () => openDetail(issue),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: window.isLoadingMore
              ? const Padding(
                  key: periodicalLoadMoreKey,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              : const SizedBox(height: 16),
        ),
      ];
    }
    if (issuesAsync?.hasError ?? false) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Couldn't load the issues. Please try again.",
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
                if (uid != null)
                  TextButton(
                    onPressed: () => ref
                        .read(issueListControllerProvider(uid).notifier)
                        .refresh(),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ];
    }
    // First load (or a uid-less first frame): one spinner, not per section.
    return [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
    ];
  }
}
