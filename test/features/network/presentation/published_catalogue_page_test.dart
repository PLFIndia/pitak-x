import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/application/published_catalogue_cover_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/domain/published_events_fetcher.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_page.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/network/presentation/widgets/published_catalogue_messages.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../support/a11y.dart';

/// The native catalogue viewer's states and actions (ADR 0015, viewer plan
/// S4). The fetcher and the browser hand-off are injected, so these tests
/// assert both what the user sees and what the app DOES NOT do: no external
/// launch from a normal action, no extra request from a filter, no write.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  PublishedCatalogueItem item(
    int index, {
    required String title,
    PublishedItemKind kind = PublishedItemKind.book,
    String? author,
    String? language,
    AgeGroup? ageGroup,
    PublishedIssueDetails? issue,
    String? coverUrl,
  }) => PublishedCatalogueItem(
    sourceIndex: index,
    title: title,
    kind: kind,
    author: author,
    language: language,
    ageGroup: ageGroup,
    issue: issue,
    coverUrl: coverUrl,
  );

  PublishedCatalogue catalogueOf(
    List<PublishedCatalogueItem> items, {
    int schemaVersion = 1,
    int? exportedAt,
    int droppedItems = 0,
    int duplicateSeriesUids = 0,
    PublishedCatalogueWarnings? warnings,
    List<PublishedPeriodical> periodicals = const [],
  }) => PublishedCatalogue(
    declaredSchemaVersion: schemaVersion,
    exportedAt: exportedAt,
    items: items,
    periodicals: periodicals,
    warnings:
        warnings ??
        PublishedCatalogueWarnings(
          droppedItems: droppedItems,
          duplicateSeriesUids: duplicateSeriesUids,
        ),
  );

  final catalogue = catalogueOf([
    item(
      0,
      title: 'The Water Margin',
      author: "Shi Nai'an",
      language: 'English',
      ageGroup: AgeGroup.above10,
    ),
    item(
      1,
      title: 'Chandamama — Vol 249 No 10',
      kind: PublishedItemKind.magazineIssue,
      language: 'Telugu',
      issue: const PublishedIssueDetails(
        periodicalUid: 'chandamama',
        volume: 249,
        issueNumber: 10,
      ),
    ),
    item(
      2,
      title: 'Kannada Picture Dictionary',
      kind: PublishedItemKind.other,
      language: 'Kannada',
      ageGroup: AgeGroup.above6,
    ),
  ], exportedAt: 1760000000000);

  /// The three catalogue items without the warnings/exportedAt wrapper.
  List<PublishedCatalogueItem> catalogueItems() => catalogue.items;

  late _RecordingLauncher launcher;
  late ProviderContainer container;

  void makeContainer(
    Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> Function(
      String url, {
      Future<void>? abortTrigger,
    })
    fetch, {
    PublishedEventsFetcher? eventsFetcher,
    _CoverPort? coverPort,
    bool coverConsent = true,
    bool coverSettingsFail = false,
    Future<PublishedCatalogueView> Function(
      PublishedCatalogue catalogue,
      PublishedCatalogueQuery query,
    )?
    queryRunner,
    void Function(PublishedCatalogueQuery query)? onQuery,
  }) {
    container = ProviderContainer(
      overrides: [
        publishedCatalogueFetcherProvider(site).overrideWithValue(fetch),
        publishedEventsFetcherProvider(site).overrideWithValue(
          eventsFetcher ?? (url, {abortTrigger}) async => const Right(null),
        ),
        // The real engine, synchronously: the isolate adapter has its own
        // suite; page tests must be deterministic.
        publishedCatalogueQueryRunnerProvider.overrideWithValue(
          queryRunner ??
              (catalogue, query) async {
                onQuery?.call(query);
                return PublishedQueryEngine.apply(catalogue, query);
              },
        ),
        // Covers are off the network here too: the port is a fake and the
        // consent switch is explicit, so no test depends on shared prefs.
        publishedCoverFetcherProvider(
          site,
        ).overrideWithValue((coverPort ?? _CoverPort(_jpeg(10, 20, 30))).call),
        settingsRepositoryProvider.overrideWith(
          (ref) async => coverSettingsFail
              ? _FailingSettings()
              : _SettingsRepo(loadRemoteCovers: coverConsent),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> pumpViewer(
    WidgetTester tester, {
    NetworkLibrary? row,
    String siteUrl = site,
    PublishedSiteOpener? opener,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    launcher = _RecordingLauncher();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PublishedCataloguePage(
            row:
                row ??
                const NetworkLibrary(siteUrl: site, name: 'Kadugodi Library'),
            opener:
                opener ??
                PublishedSiteOpener(
                  launch: (url, mode) => launcher.launch(url, mode),
                ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    launcher = _RecordingLauncher();
  });

  group('states', () {
    testWidgets('loading shows a spinner and the browser action', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      await tester.pump();

      expect(find.text('Loading this published catalogue…'), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.byTooltip('Reload catalogue'), findsOneWidget);

      await tester.tap(find.byTooltip('Open in browser'));
      await tester.pump();
      expect(launcher.calls, hasLength(1));
      expect(launcher.calls.single.toString(), site);
      expect(launcher.modes.single, LaunchMode.externalApplication);
    });

    testWidgets('success shows the catalogue, count and badges', (
      tester,
    ) async {
      makeContainer(_immediate(catalogue));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text('The Water Margin'), findsOneWidget);
      expect(find.text("Shi Nai'an"), findsOneWidget);
      expect(find.text('3 of 3 items'), findsOneWidget);
      expect(find.text('Above 10'), findsOneWidget);
      expect(find.text('Issue'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      // The Other row never shows book-only author metadata.
      expect(find.text("Shi Nai'an"), findsOneWidget);
      // Publish-time context, never a live claim.
      expect(find.textContaining('snapshot from publish time'), findsOneWidget);
    });

    testWidgets('a newer schema shows a persistent warning', (tester) async {
      makeContainer(
        _immediate(catalogueOf(catalogueItems(), schemaVersion: 2)),
      );
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('published by a newer Pitak'), findsOneWidget);
      // The warning survives a result-count update (the web viewer's bug this
      // plan explicitly avoids).
      await tester.enterText(find.byType(TextField), 'water');
      await tester.pump(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 items'), findsOneWidget);
      expect(find.textContaining('published by a newer Pitak'), findsOneWidget);
    });

    testWidgets('an empty payload says so, not "no matches"', (tester) async {
      makeContainer(_immediate(catalogueOf(const [])));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text('This published catalogue is empty.'), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.textContaining('No matches'), findsNothing);
    });

    testWidgets('a payload with no readable rows is distinct from empty', (
      tester,
    ) async {
      makeContainer(_immediate(catalogueOf(const [], droppedItems: 2)));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text('No readable items.'), findsOneWidget);
      expect(find.text('This published catalogue is empty.'), findsNothing);
    });

    testWidgets('a duplicate-only catalogue still shows the safe warning', (
      tester,
    ) async {
      // Review finding 8: the visible gate, not merely the counter.
      makeContainer(
        _immediate(catalogueOf(catalogueItems(), duplicateSeriesUids: 1)),
      );
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text("Some entries couldn't be displayed."), findsOneWidget);
      // The same safe sentence as every other partial read: no UID, title or
      // count from the hostile payload is printed.
      expect(find.textContaining('chandamama'), findsNothing);
      expect(find.textContaining('duplicate'), findsNothing);
    });

    testWidgets('a clean catalogue shows no partial-read warning', (
      tester,
    ) async {
      makeContainer(_immediate(catalogueOf(catalogueItems())));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text("Some entries couldn't be displayed."), findsNothing);
    });

    testWidgets('partial reads warn without printing remote values', (
      tester,
    ) async {
      makeContainer(_immediate(catalogueOf(catalogueItems(), droppedItems: 1)));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text("Some entries couldn't be displayed."), findsOneWidget);
    });

    testWidgets('an identity conflict is shown and not "repaired"', (
      tester,
    ) async {
      makeContainer(_immediate(catalogue));
      await pumpViewer(
        tester,
        row: const NetworkLibrary(
          siteUrl: site,
          name: 'Kadugodi Library',
          fetchStatus: FetchStatus.identityConflict,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('published identity has changed'),
        findsOneWidget,
      );
      // Read-only: no merge/repair action exists.
      expect(find.textContaining('Merge'), findsNothing);
      expect(find.textContaining('Update fingerprint'), findsNothing);
    });
  });

  group('errors', () {
    Future<void> expectError(
      WidgetTester tester,
      PublishedCatalogueFailureReason reason,
      String message,
    ) async {
      makeContainer(
        (url, {abortTrigger}) async => Left(PublishedCatalogueFailure(reason)),
      );
      await pumpViewer(tester);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget, reason: '$reason');
      expect(find.text('Open in browser'), findsOneWidget);
    }

    testWidgets('http status makes no 404/never-published claim', (
      tester,
    ) async {
      await expectError(
        tester,
        PublishedCatalogueFailureReason.httpStatus,
        "The site didn't serve this catalogue.",
      );
      expect(find.textContaining('404'), findsNothing);
      expect(find.textContaining('not published'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('transport and timeout offer Retry', (tester) async {
      await expectError(
        tester,
        PublishedCatalogueFailureReason.transport,
        "Couldn't reach this library. Check your connection and try again.",
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('too large keeps the browser prominent and offers no retry', (
      tester,
    ) async {
      await expectError(
        tester,
        PublishedCatalogueFailureReason.tooLarge,
        'This catalogue is too large to open in Pitak.',
      );
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('invalid bytes stay a safe message', (tester) async {
      await expectError(
        tester,
        PublishedCatalogueFailureReason.invalid,
        "Pitak couldn't read this published catalogue.",
      );
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a corrupted saved URL never launches the browser', (
      tester,
    ) async {
      makeContainer(_immediate(catalogue));
      await pumpViewer(
        tester,
        siteUrl: 'https://evil.example/pitak/',
        row: const NetworkLibrary(
          siteUrl: 'https://evil.example/pitak/',
          name: 'Bad Row',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text("This library's address can't be opened in Pitak."),
        findsOneWidget,
      );
      // The AppBar action is the only browser entry point; tapping it must
      // refuse WITHOUT a launch and show the app's one safe message.
      await tester.tap(find.byTooltip('Open in browser'));
      await tester.pump();
      expect(launcher.calls, isEmpty);
      expect(find.text("Couldn't open that link."), findsOneWidget);
    });

    testWidgets('a launcher failure shows the safe message, not the error', (
      tester,
    ) async {
      makeContainer(_immediate(catalogue));
      await pumpViewer(
        tester,
        opener: PublishedSiteOpener(
          launch: (url, mode) async => throw StateError('platform said no'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open in browser'));
      await tester.pump();
      expect(find.text("Couldn't open that link."), findsOneWidget);
      expect(find.textContaining('platform said no'), findsNothing);
    });

    testWidgets('Retry performs exactly one more request', (tester) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.failLatest(
        const PublishedCatalogueFailure(
          PublishedCatalogueFailureReason.transport,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(pending.calls, hasLength(2));
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();
      expect(find.text('The Water Margin'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('Reload performs exactly one more request', (tester) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();
      expect(pending.calls, hasLength(2));
      // A second tap while the reload runs must not add a request.
      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();
      expect(pending.calls, hasLength(2));
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();
    });

    testWidgets('the browser action opens the saved site externally', (
      tester,
    ) async {
      makeContainer(_immediate(catalogue));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open in browser'));
      await tester.pump();
      expect(launcher.calls, hasLength(1));
      expect(launcher.calls.single.toString(), site);
      expect(launcher.modes.single, LaunchMode.externalApplication);
    });

    testWidgets('search, kind filter and sort never refetch', (tester) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();
      expect(pending.calls, hasLength(1));

      await tester.enterText(find.byType(TextField), 'water');
      await tester.pump(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 items'), findsOneWidget);

      // Clear the search, then use the kind chip.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Others'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 items'), findsOneWidget);
      expect(find.text('Kannada Picture Dictionary'), findsOneWidget);
      expect(find.text('The Water Margin'), findsNothing);

      // Sort: open the menu and pick Language.
      await tester.tap(find.text('Published order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language').last);
      await tester.pumpAndSettle();
      expect(pending.calls, hasLength(1), reason: 'still one GET');
      expect(
        container.read(publishedCatalogueQueryControllerProvider(site)).sort,
        PublishedSortOrder.language,
      );
    });

    testWidgets('no matches offers a clear action that does not refetch', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nothing-matches');
      await tester.pump(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();
      expect(find.text('No matches.'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('The Water Margin'), findsOneWidget);
      expect(pending.calls, hasLength(1));
    });

    testWidgets('detail navigation keeps the catalogue and the query', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'water');
      await tester.pump(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('The Water Margin'));
      await tester.pumpAndSettle();
      expect(find.text('Published item'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text("Shi Nai'an"), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 items'), findsOneWidget);
      expect(find.text('water'), findsOneWidget);
      expect(pending.calls, hasLength(1), reason: 'no refetch on return');
    });
  });

  group('derived query failure', () {
    testWidgets('a failed query is a safe retryable state, never a spinner', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      var calls = 0;
      var failNext = true;
      makeContainer(
        pending.call,
        queryRunner: (loaded, query) async {
          calls++;
          if (failNext) {
            failNext = false;
            throw StateError('sentinel-worker-detail');
          }
          return PublishedQueryEngine.apply(loaded, query);
        },
      );
      await pumpViewer(tester);
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();

      expect(
        find.text(PublishedCatalogueQueryErrorSliver.message),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      // No endless spinner, no stale rows, no stale count, no raw error text.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('The Water Margin'), findsNothing);
      expect(find.textContaining('of 3 items'), findsNothing);
      expect(find.textContaining('sentinel-worker-detail'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(pending.calls, hasLength(1), reason: 'the catalogue is loaded');

      // A query-intent change while the results area is failed must not make
      // the state worse, and must survive the retry.
      failNext = true;
      await tester.enterText(find.byType(TextField), 'water');
      await tester.pump(
        publishedSearchDebounce + const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(PublishedCatalogueQueryErrorSliver.message),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 3, reason: 'retry runs the derived query again');
      expect(
        pending.calls,
        hasLength(1),
        reason: 'never refetches the payload',
      );
      expect(find.text('1 of 3 items'), findsOneWidget);
      expect(find.text('The Water Margin'), findsOneWidget);
      final state = container.read(
        publishedCatalogueQueryControllerProvider(site),
      );
      expect(state.search, 'water');
      expect(state.activeSearch, 'water');
      expect(
        find.text(PublishedCatalogueQueryErrorSliver.message),
        findsNothing,
      );
    });

    testWidgets('a failure after a rendered view hides the stale rows', (
      tester,
    ) async {
      // `valueOrNull` keeps the previous view during a new pass; an error must
      // not be presented as "this filter succeeded".
      final pending = _PendingFetcher();
      final covers = _CoverPort(_jpeg(10, 20, 30));
      var calls = 0;
      var failNext = false;
      makeContainer(
        pending.call,
        coverPort: covers,
        queryRunner: (loaded, query) async {
          calls++;
          if (failNext) {
            failNext = false;
            throw StateError('sentinel-worker-detail');
          }
          return PublishedQueryEngine.apply(loaded, query);
        },
      );
      await pumpViewer(tester);
      pending.completeLatest(
        catalogueOf([
          item(
            0,
            title: 'The Water Margin',
            kind: PublishedItemKind.other,
            language: 'English',
            coverUrl: 'covers/water.jpg',
          ),
          item(1, title: 'Kannada Picture Dictionary', language: 'Kannada'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('The Water Margin'), findsOneWidget);
      expect(find.text('2 of 2 items'), findsOneWidget);
      expect(covers.calls, hasLength(1));

      failNext = true;
      await tester.tap(find.widgetWithText(ChoiceChip, 'Others'));
      await tester.pumpAndSettle();

      expect(
        find.text(PublishedCatalogueQueryErrorSliver.message),
        findsOneWidget,
      );
      expect(find.text('The Water Margin'), findsNothing);
      expect(find.textContaining('of 2 items'), findsNothing);
      expect(find.textContaining('No matches'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 3);
      expect(pending.calls, hasLength(1), reason: 'retry is query-only');
      // The "Others" filter is still in force: the book is gone, the other item
      // (the covered one) is back.
      expect(find.text('The Water Margin'), findsOneWidget);
      expect(find.text('Kannada Picture Dictionary'), findsNothing);
      // The cover session was never reset, so the visible row reuses its
      // cached image instead of downloading it again.
      expect(covers.calls, hasLength(1));
      expect(find.byType(Image), findsOneWidget);
      // The kind filter that exposed the failure is still in force.
      expect(
        container.read(publishedCatalogueQueryControllerProvider(site)).kind,
        PublishedKindFilter.others,
      );
    });
  });

  group('language facet across a reload', () {
    /// Two items, one per language, so the row count proves the real filter.
    PublishedCatalogue englishAndHindi(String englishSpelling) => catalogueOf([
      item(0, title: 'English Book', language: englishSpelling),
      item(1, title: 'Hindi Book', language: 'Hindi'),
    ]);

    Future<void> selectLanguage(WidgetTester tester, String label) async {
      expect(find.text('All languages'), findsOneWidget);
      await tester.tap(find.text('All languages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a case-only facet change remaps the real selection', (
      tester,
    ) async {
      // Review finding 3: the dropdown is controlled, so keeping a selection
      // the new facet list does not contain asserted in debug and left an
      // invisible filter in release.
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(englishAndHindi('English'));
      await tester.pumpAndSettle();

      await selectLanguage(tester, 'English');
      expect(
        container
            .read(publishedCatalogueQueryControllerProvider(site))
            .language,
        'English',
      );
      expect(find.text('1 of 2 items'), findsOneWidget);

      // The same language, re-spelled by the new payload.
      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();
      expect(pending.calls, hasLength(2), reason: 'one deliberate reload');
      pending.completeLatest(englishAndHindi('ENGLISH'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no dropdown assertion');
      final state = container.read(
        publishedCatalogueQueryControllerProvider(site),
      );
      expect(state.language, 'ENGLISH');
      // The filter is real: the Hindi row stays hidden and no GET was added by
      // the reconciliation itself.
      expect(find.text('1 of 2 items'), findsOneWidget);
      expect(find.text('Hindi Book'), findsNothing);
      expect(pending.calls, hasLength(2));
    });

    testWidgets('a removed facet clears the selection and the filter', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(englishAndHindi('English'));
      await tester.pumpAndSettle();
      await selectLanguage(tester, 'English');
      expect(find.text('1 of 2 items'), findsOneWidget);

      // The reloaded payload no longer offers that language at all.
      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();
      pending.completeLatest(
        catalogueOf([
          item(0, title: 'Hindi Book', language: 'Hindi'),
          item(1, title: 'Tamil Book', language: 'Tamil'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no dropdown assertion');
      expect(
        container
            .read(publishedCatalogueQueryControllerProvider(site))
            .language,
        isNull,
      );
      expect(find.text('All languages'), findsOneWidget);
      // No invisible filter survives: both rows are visible again.
      expect(find.text('2 of 2 items'), findsOneWidget);
      expect(find.text('Hindi Book'), findsOneWidget);
      expect(find.text('Tamil Book'), findsOneWidget);
      expect(pending.calls, hasLength(2));
    });
  });

  group('cover session', () {
    /// A catalogue whose only covered row is the first item, so exactly one
    /// `Image` can appear on screen.
    PublishedCatalogue coveredCatalogue() => catalogueOf([
      item(0, title: 'The Water Margin', coverUrl: 'covers/water.jpg'),
      item(
        1,
        title: 'Kannada Picture Dictionary',
        kind: PublishedItemKind.other,
      ),
    ]);

    Uint8List renderedCoverBytes(WidgetTester tester) {
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(1), reason: 'one covered row is visible');
      final provider = images.single.image;
      expect(provider, isA<MemoryImage>());
      return (provider as MemoryImage).bytes;
    }

    testWidgets('a reload re-fetches an unchanged cover URL', (tester) async {
      // Review finding 2: keeping the URL as the cache key means an image that
      // changed behind the same URL would otherwise stay stale forever.
      final pending = _PendingFetcher();
      final covers = _CoverPort(_jpeg(10, 20, 30));
      makeContainer(pending.call, coverPort: covers);
      await pumpViewer(tester);
      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();

      expect(covers.calls, hasLength(1));
      expect(renderedCoverBytes(tester), same(covers.served.single));

      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();
      expect(pending.calls, hasLength(2), reason: 'the reload started');
      // While the catalogue GET is pending, the visible rows belong to the OLD
      // payload: no replacement cover request may start.
      expect(covers.calls, hasLength(1), reason: 'covers are paused');

      covers.bytes = _jpeg(200, 210, 220);
      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();

      expect(covers.calls, hasLength(2), reason: 'one new fetch');
      expect(
        covers.calls.last.url,
        covers.calls.first.url,
        reason: 'the URL did not change — only the image did',
      );
      final rendered = renderedCoverBytes(tester);
      expect(rendered, same(covers.served.last), reason: 'B is on screen');
      expect(rendered, isNot(same(covers.served.first)), reason: 'not A');
    });

    testWidgets('a reload aborts old cover work and discards late bytes', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      final covers = _CoverPort(_jpeg(10, 20, 30))..manual = true;
      makeContainer(pending.call, coverPort: covers);
      await pumpViewer(tester);
      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();
      expect(covers.calls, hasLength(1));
      var aborted = false;
      unawaited(covers.aborts.single.then((_) => aborted = true));

      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();
      expect(aborted, isTrue, reason: 'reset completes the caller abort');

      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();
      // The old socket's late result must not be cached in the new session;
      // completing it is what releases the single FIFO worker.
      covers.completeCall(0, _jpeg(1, 2, 3));
      await tester.pumpAndSettle();
      expect(
        container.read(publishedCatalogueCoverControllerProvider(site)).isEmpty,
        isTrue,
        reason: 'the old payload never lands in the new session',
      );
      expect(find.byType(Image), findsNothing);

      // The new generation then refreshes the visible row normally.
      expect(covers.calls, hasLength(2));
      covers.completeCall(1, _jpeg(4, 5, 6));
      await tester.pumpAndSettle();
      expect(renderedCoverBytes(tester), same(covers.served.last));
    });

    testWidgets('a double Reload tap is one GET and one cover reset', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      final covers = _CoverPort(_jpeg(10, 20, 30));
      makeContainer(pending.call, coverPort: covers);
      await pumpViewer(tester);
      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();
      expect(covers.calls, hasLength(1));

      final resets = <PublishedCoverSession>[];
      final sub = container.listen(
        publishedCatalogueCoverControllerProvider(site),
        (previous, next) {
          if (previous != null && !previous.isEmpty && next.isEmpty) {
            resets.add(next);
          }
        },
      );
      addTearDown(sub.close);

      // Two taps in the SAME frame: the second must see `canRefresh == false`.
      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pump();

      expect(pending.calls, hasLength(2), reason: 'exactly one extra GET');
      expect(resets, hasLength(1), reason: 'exactly one cover reset cycle');
      expect(covers.calls, hasLength(1), reason: 'no cover work from the tap');

      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();
      expect(
        covers.calls,
        hasLength(2),
        reason: 'one refresh after the reload',
      );
    });

    testWidgets('an off-screen session image is released on reset', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      final covers = _CoverPort(_jpeg(10, 20, 30));
      makeContainer(pending.call, coverPort: covers);
      await pumpViewer(tester);
      pending.completeLatest(
        catalogueOf([
          item(0, title: 'First Covered', coverUrl: 'covers/first.jpg'),
          for (var i = 1; i < 40; i++) item(i, title: 'Plain Row $i'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(covers.calls, hasLength(1));

      final cache = PaintingBinding.instance.imageCache;
      final key = MemoryImage(covers.served.single);
      addTearDown(() => cache.evict(key));
      expect(cache.statusForKey(key).tracked, isTrue);

      // Scroll the covered row out of the tree: its widget is disposed but the
      // session (and therefore the global cache entry) still holds the image.
      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Plain Row 39'),
        600,
        scrollable: scrollable.first,
      );
      await tester.pumpAndSettle();
      expect(find.text('First Covered'), findsNothing);
      expect(
        cache.statusForKey(key).tracked,
        isTrue,
        reason: 'the bytes are still in the Riverpod session',
      );

      container
          .read(publishedCatalogueCoverControllerProvider(site).notifier)
          .reset();
      await tester.pumpAndSettle();
      expect(
        cache.statusForKey(key).tracked,
        isFalse,
        reason: 'reset releases images no widget owns any more',
      );
    });

    testWidgets("reset and teardown untrack only this session's images", (
      tester,
    ) async {
      final pending = _PendingFetcher();
      final covers = _CoverPort(_jpeg(10, 20, 30));
      makeContainer(pending.call, coverPort: covers);
      await pumpViewer(tester);
      pending.completeLatest(coveredCatalogue());
      await tester.pumpAndSettle();

      final cache = PaintingBinding.instance.imageCache;
      final firstKey = MemoryImage(covers.served.single);
      // An unrelated image belongs to another screen: it must survive.
      final unrelatedKey = MemoryImage(Uint8List.fromList(const [7, 7, 7]));
      cache.putIfAbsent(
        unrelatedKey,
        () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
      );
      addTearDown(() {
        cache
          ..evict(firstKey)
          ..evict(unrelatedKey);
      });
      expect(cache.statusForKey(firstKey).tracked, isTrue);
      expect(cache.statusForKey(unrelatedKey).tracked, isTrue);

      covers.bytes = _jpeg(200, 210, 220);
      container
          .read(publishedCatalogueCoverControllerProvider(site).notifier)
          .reset();
      await tester.pumpAndSettle();
      expect(
        cache.statusForKey(firstKey).tracked,
        isFalse,
        reason: 'the reset session released its old image',
      );
      expect(
        cache.statusForKey(unrelatedKey).tracked,
        isTrue,
        reason: 'cleanup is session-scoped, never a global clear',
      );

      // The visible row rendered the new generation, so a second key exists…
      final secondKey = MemoryImage(covers.served.last);
      expect(secondKey, isNot(firstKey));
      expect(cache.statusForKey(secondKey).tracked, isTrue);

      // …and unmounting the whole viewer route releases it.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
      expect(
        cache.statusForKey(secondKey).tracked,
        isFalse,
        reason: 'route teardown evicts the session images',
      );
    });
  });

  group('announcements and events', () {
    PublishedEvents events() => PublishedEvents(
      declaredSchemaVersion: 1,
      posters: const [
        PublishedEventPoster(
          imageRef: 'posters/story.jpg',
          description: 'Story hour on Saturday',
        ),
      ],
    );

    testWidgets('shows native posters and Reload refreshes events.json', (
      tester,
    ) async {
      var eventFetches = 0;
      final covers = _CoverPort(_jpeg(20, 30, 40));
      makeContainer(
        _immediate(catalogue),
        eventsFetcher: (url, {abortTrigger}) async {
          eventFetches++;
          expect(url, 'https://kadugodi.github.io/pitak/events.json');
          return Right(events());
        },
        coverPort: covers,
      );
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text('Announcements & Events'), findsOneWidget);
      expect(find.text('Story hour on Saturday'), findsOneWidget);
      expect(eventFetches, 1);
      expect(
        covers.calls.map((request) => request.url),
        contains('https://kadugodi.github.io/pitak/posters/story.jpg'),
      );

      await tester.tap(find.byTooltip('Reload catalogue'));
      await tester.pumpAndSettle();
      expect(eventFetches, 2);
    });

    testWidgets('poster-only catalogue offers the same explicit image opt-in', (
      tester,
    ) async {
      final covers = _CoverPort(_jpeg(20, 30, 40));
      makeContainer(
        _immediate(catalogue),
        eventsFetcher: (url, {abortTrigger}) async => Right(events()),
        coverPort: covers,
        coverConsent: false,
      );
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      expect(find.text('Load covers'), findsOneWidget);
      expect(covers.calls, isEmpty);
      await tester.tap(find.text('Load covers'));
      await tester.pumpAndSettle();

      expect(find.text('Load covers'), findsNothing);
      expect(
        covers.calls.map((request) => request.url),
        contains('https://kadugodi.github.io/pitak/posters/story.jpg'),
      );
    });

    testWidgets(
      'an events failure is retryable without blocking the catalogue',
      (tester) async {
        var attempts = 0;
        makeContainer(
          _immediate(catalogue),
          eventsFetcher: (url, {abortTrigger}) async {
            attempts++;
            if (attempts == 1) return const Left(NetworkFailure());
            return const Right(null);
          },
        );
        await pumpViewer(tester);
        await tester.pumpAndSettle();

        expect(find.text('The Water Margin'), findsOneWidget);
        expect(
          find.text('Couldn’t load announcements and events.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Retry events'));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(
          find.text('Couldn’t load announcements and events.'),
          findsNothing,
        );
      },
    );
  });

  group('layout and accessibility', () {
    testWidgets('long Indic titles wrap instead of overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      makeContainer(
        _immediate(
          catalogueOf([
            item(
              0,
              title:
                  'ಕನ್ನಡ ಸಾಹಿತ್ಯದ ಒಂದು ಬಹಳ ಉದ್ದವಾದ ಪುಸ್ತಕದ ಹೆಸರು ಮತ್ತು ಅದರ '
                  'ಉಪಶೀರ್ಷಿಕೆ — ಇದು ಪರದೆಯ ಅಗಲಕ್ಕಿಂತ ಹೆಚ್ಚು ಉದ್ದವಾಗಿದೆ',
              author: 'ಒಬ್ಬ ಬರಹಗಾರ',
            ),
          ]),
        ),
      );
      await pumpViewer(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large catalogue builds rows lazily as they scroll', (
      tester,
    ) async {
      final many = <PublishedCatalogueItem>[
        for (var i = 0; i < 200; i++) item(i, title: 'Bulk Row $i'),
      ];
      makeContainer(_immediate(catalogueOf(many)));
      await pumpViewer(tester);
      await tester.pumpAndSettle();

      final built = tester
          .widgetList<Text>(find.textContaining('Bulk Row '))
          .length;
      expect(
        built,
        lessThan(60),
        reason: 'an eager list would build all 200 rows at once',
      );

      final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Bulk Row 199'),
        600,
        scrollable: scrollable.first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Bulk Row 199'), findsOneWidget);
    });

    testWidgets('background/resume causes zero additional fetches', (
      tester,
    ) async {
      final pending = _PendingFetcher();
      makeContainer(pending.call);
      await pumpViewer(tester);
      pending.completeLatest(catalogue);
      await tester.pumpAndSettle();
      expect(pending.calls, hasLength(1));

      // The app-lock gate paints over the route; the route itself stays
      // mounted, so a pause/resume cycle must not refetch anything.
      // Flutter's lifecycle machine requires the full walked sequence.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(pending.calls, hasLength(1));
      expect(find.text('The Water Margin'), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      makeContainer(_immediate(catalogue));
      await pumpViewer(tester);
      await tester.pumpAndSettle();
      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets('meets accessibility guidelines in dark theme', (tester) async {
      makeContainer(_immediate(catalogue));
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: PublishedCataloguePage(
              row: const NetworkLibrary(siteUrl: site, name: 'Kadugodi'),
              opener: PublishedSiteOpener(
                launch: (url, mode) => launcher.launch(url, mode),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectMeetsA11yGuidelines(tester);
    });
  });
}

/// An immediate fetcher returning [catalogue].
Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> Function(
  String url, {
  Future<void>? abortTrigger,
})
_immediate(PublishedCatalogue catalogue) =>
    (url, {abortTrigger}) async => Right(catalogue);

/// A controllable fetcher.
final class _PendingFetcher {
  final List<String> calls = [];
  final List<Completer<Either<PublishedCatalogueFailure, PublishedCatalogue>>>
  _pending = [];

  Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> call(
    String url, {
    Future<void>? abortTrigger,
  }) {
    calls.add(url);
    final completer =
        Completer<Either<PublishedCatalogueFailure, PublishedCatalogue>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeLatest(PublishedCatalogue catalogue) =>
      _pending.last.complete(Right(catalogue));

  void failLatest(PublishedCatalogueFailure failure) =>
      _pending.last.complete(Left(failure));
}

/// A small valid JPEG of one colour: real decodable bytes for `Image.memory`.
Uint8List _jpeg(int r, int g, int b) => Uint8List.fromList(
  img.encodeJpg(img.Image(width: 4, height: 6)..clear(img.ColorRgb8(r, g, b))),
);

/// A controllable cover port. Each success hands back a FRESH buffer, exactly
/// like the real adapter (which decodes into new bytes on every request), so a
/// reload under the same URL really is a new `MemoryImage` key.
final class _CoverPort {
  _CoverPort(this.bytes);

  /// The payload the next successful request returns.
  Uint8List bytes;

  /// Every request the scheduler made, in order.
  final List<PublishedCoverRequest> calls = [];

  /// The caller-abort signals, in call order.
  final List<Future<void>> aborts = [];

  /// The exact buffers this port produced, in completion order (the discarded
  /// late result included — that is what the abort test needs to prove).
  final List<Uint8List> served = [];

  final List<Completer<Uint8List?>> _pending = [];

  /// When true, requests stay pending until the test completes them.
  bool manual = false;

  Future<Uint8List?> call(
    PublishedCoverRequest request, {
    Future<void>? abortTrigger,
  }) {
    calls.add(request);
    if (abortTrigger != null) aborts.add(abortTrigger);
    if (manual) {
      final completer = Completer<Uint8List?>();
      _pending.add(completer);
      return completer.future;
    }
    final copy = Uint8List.fromList(bytes);
    served.add(copy);
    return Future<Uint8List?>.value(copy);
  }

  /// Completes the [index]th request. An aborted one is still completable: that
  /// is how a test proves obsolete bytes are discarded rather than cached.
  void completeCall(int index, Uint8List value) {
    final copy = Uint8List.fromList(value);
    served.add(copy);
    _pending[index].complete(copy);
  }
}

/// A settings repository with only the cover switch meaningful.
class _SettingsRepo implements SettingsRepository {
  _SettingsRepo({required this.loadRemoteCovers});

  final bool loadRemoteCovers;

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(loadRemoteCovers: loadRemoteCovers);

  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) async =>
      right(unit);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call');
}

/// A settings repository that never loads (fail closed).
class _FailingSettings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => throw StateError('settings unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call');
}

/// Records every browser hand-off attempt.
final class _RecordingLauncher {
  final List<Uri> calls = [];
  final List<LaunchMode> modes = [];

  Future<bool> launch(Uri url, LaunchMode mode) async {
    calls.add(url);
    modes.add(mode);
    return true;
  }
}
