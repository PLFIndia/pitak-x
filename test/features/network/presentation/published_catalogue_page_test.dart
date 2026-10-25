import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_page.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
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
  }) => PublishedCatalogueItem(
    sourceIndex: index,
    title: title,
    kind: kind,
    author: author,
    language: language,
    ageGroup: ageGroup,
    issue: issue,
  );

  PublishedCatalogue catalogueOf(
    List<PublishedCatalogueItem> items, {
    int schemaVersion = 1,
    int? exportedAt,
    int droppedItems = 0,
    List<PublishedPeriodical> periodicals = const [],
  }) => PublishedCatalogue(
    declaredSchemaVersion: schemaVersion,
    exportedAt: exportedAt,
    items: items,
    periodicals: periodicals,
    warnings: PublishedCatalogueWarnings(droppedItems: droppedItems),
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
    fetch,
  ) {
    container = ProviderContainer(
      overrides: [
        publishedCatalogueFetcherProvider(site).overrideWithValue(fetch),
        // The real engine, synchronously: the isolate adapter has its own
        // suite; page tests must be deterministic.
        publishedCatalogueQueryRunnerProvider.overrideWithValue(
          (catalogue, query) async =>
              PublishedQueryEngine.apply(catalogue, query),
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
