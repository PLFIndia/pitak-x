/// On-device journey for the native published-catalogue viewer (ADR 0015,
/// viewer plan S6). Run by hand before a release, like the sibling smoke
/// journeys:
///
///   flutter test integration_test/published_catalogue_smoke_test.dart \
///     --flavor fdroid -d <device>
///
/// Real SQLite, real preferences, real navigation and real settings; only the
/// catalogue and cover PORTS are fakes, because the automated suite must never
/// depend on the public internet. The journey:
///
///   add a uniquely named bookmark through the UI → open it → search, filter,
///   read-only detail → back with state intact → reload once → browser action
///   through the injected seam → remove the test row.
///
/// Nothing here reads or writes a live host, and the row is removed at the end
/// so a rerun on the same install starts clean.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_page.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';

import 'smoke_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('published catalogue viewer journey', (tester) async {
    final stamp = smokeStamp().toLowerCase();
    final site = 'https://smoke-$stamp.github.io/lib/';
    final name = 'Smoke Library $stamp';

    PublishedCatalogueItem item(int index, String title, {String? language}) =>
        PublishedCatalogueItem(
          sourceIndex: index,
          title: title,
          kind: PublishedItemKind.book,
          author: 'Smoke Author',
          language: language,
        );

    final catalogue = PublishedCatalogue(
      declaredSchemaVersion: 1,
      exportedAt: 1760000000000,
      items: [
        item(0, 'Smoke Book One', language: 'English'),
        item(1, 'Smoke Book Two', language: 'Hindi'),
        item(2, 'Smoke Book Three', language: 'English'),
      ],
      periodicals: const [],
    );

    var catalogueFetches = 0;
    final launches = <Uri>[];

    final container = ProviderContainer(
      overrides: [
        publishedCatalogueFetcherProvider(site).overrideWithValue((
          url, {
          abortTrigger,
        }) async {
          catalogueFetches++;
          return Right(catalogue);
        }),
        publishedCatalogueQueryRunnerProvider.overrideWithValue(
          (loaded, query) async => PublishedQueryEngine.apply(loaded, query),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: NetworkPage(
            publishedSiteOpener: PublishedSiteOpener(
              launch: (url, mode) async {
                launches.add(url);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // --- add the bookmark through the real dialog + Drift rows -------------
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add bookmark'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    // Field order in the dialog: Link first, then the optional name.
    await tester.enterText(fields.at(0), site);
    await tester.enterText(fields.at(1), name);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // ONE local finder for this run's row, used by every step below and by
    // both cleanup paths, so "the row this journey created" can never drift
    // from "the row that gets removed".
    final generatedTile = find.widgetWithText(NetworkLibraryTile, name);
    final networkScrollable = find.descendant(
      of: find.byType(NetworkPage),
      matching: find.byType(CustomScrollView),
    );

    // The list builds tiles lazily, so a newly added row below the fold is not
    // in the element tree yet.
    await reveal(tester, generatedTile, scrollable: networkScrollable);

    var rowRemoved = false;

    /// Removes ONLY this run's row, and is safe to call twice.
    ///
    /// Why it looks at the provider first (beginner note): a failed journey can
    /// leave a pushed route on top, and a row that scrolled away is not in the
    /// widget tree at all. Asking "is this exact site/name still saved?" is
    /// unambiguous, while a bare tooltip finder may match ANOTHER saved
    /// library's Remove button — the bug this replaced.
    Future<void> removeGeneratedRow() async {
      if (rowRemoved) return;
      // A failed journey can end before the tree exists at all; there is then
      // no row on screen to clean up.
      if (find.byType(MaterialApp).evaluate().isEmpty) return;
      // Leave any pushed route (viewer or item detail). Bounded: a broken
      // navigator must not turn cleanup into an infinite loop.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (find.byType(PublishedCataloguePage).evaluate().isEmpty) break;
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      final view = appContainer(tester).read(networkListViewProvider);
      final stillSaved =
          view.valueOrNull?.rows.any(
            (row) => row.siteUrl == site && row.name == name,
          ) ??
          // An unresolved list is abnormal here; assume the row is present and
          // let the reveal below fail loudly instead of silently skipping.
          true;
      if (!stillSaved) {
        // The normal path already removed it.
        rowRemoved = true;
        return;
      }
      await reveal(tester, generatedTile, scrollable: networkScrollable);
      // Scoped to the tile: never tap an unscoped Remove tooltip, which is
      // ambiguous as soon as another saved library is visible.
      await tester.tap(
        find.descendant(of: generatedTile, matching: find.byTooltip('Remove')),
      );
      await tester.pumpAndSettle();
      expect(
        generatedTile,
        findsNothing,
        reason: 'cleanup removed only the generated row',
      );
      rowRemoved = true;
    }

    // Registered AFTER the container teardown above, so LIFO teardown runs this
    // while the provider container is still alive. It covers every failure
    // between "row created" and "row removed".
    addTearDown(removeGeneratedRow);

    // --- open the native viewer -------------------------------------------
    await tester.tap(generatedTile);
    await tester.pumpAndSettle();

    expect(find.text('Smoke Book One'), findsOneWidget);
    expect(find.text('3 of 3 items'), findsOneWidget);
    expect(catalogueFetches, 1, reason: 'one GET per explicit open');
    expect(launches, isEmpty, reason: 'the row tap never launches a browser');

    // --- search --------------------------------------------------------------
    await tester.enterText(find.byType(TextField).first, 'two');
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 items'), findsOneWidget);
    expect(find.text('Smoke Book Two'), findsOneWidget);

    // --- clear and filter by kind -------------------------------------------
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Books'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 items'), findsOneWidget);

    // --- read-only detail and back with state intact ------------------------
    await tester.tap(find.text('Smoke Book One'));
    await tester.pumpAndSettle();
    expect(find.text('Published item'), findsOneWidget);
    expect(find.text('Smoke Author'), findsOneWidget);
    expect(find.text('Lend'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 items'), findsOneWidget);
    expect(catalogueFetches, 1, reason: 'a detail round trip is not a reload');

    // --- one deliberate reload ----------------------------------------------
    await tester.tap(find.byTooltip('Reload catalogue'));
    await tester.pumpAndSettle();
    expect(catalogueFetches, 2);

    // --- browser action through the injected seam ---------------------------
    await tester.tap(find.byTooltip('Open in browser'));
    await tester.pumpAndSettle();
    expect(launches, [Uri.parse(site)]);

    // --- leave and remove the test row --------------------------------------
    await tester.pageBack();
    await tester.pumpAndSettle();
    await removeGeneratedRow();
    expect(generatedTile, findsNothing);

    // A sibling journey must not inherit this row; every OTHER saved library
    // (and the rest of the app install) is left untouched.
  });
}
