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
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
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

    expect(find.text(name), findsOneWidget);

    // --- open the native viewer -------------------------------------------
    await tester.tap(find.widgetWithText(NetworkLibraryTile, name));
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
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text(name), findsNothing);

    // A sibling journey must not inherit this row; the app install keeps the
    // rest of its data untouched.
  });
}
