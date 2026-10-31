import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/presentation/pages/library_bookmarks_page.dart';
import 'package:pitaka/features/network/presentation/widgets/network_library_tile.dart';
import 'package:pitaka/features/network/presentation/widgets/open_published_site.dart';
import 'package:pitaka/features/network/presentation/widgets/saved_libraries_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../support/published_file_fakes.dart';

/// Standalone bookmark tests also exercise the shared list and native viewer.
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';

  late _FakeRepo repo;

  Future<void> pumpPage(
    WidgetTester tester, {
    PublishedSiteOpener? opener,
    Map<String, PublishedCatalogue> catalogues = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'library_id': rawId});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWith((ref) async => repo),
          publishedSiteUrlProvider.overrideWith((ref) async => null),
          descriptorFetcherProvider.overrideWithValue(
            (url) async =>
                const DescriptorRefused(DescriptorRefusal.httpStatus),
          ),
          for (final entry in catalogues.entries) ...[
            publishedCatalogueFetcherProvider(entry.key).overrideWithValue(
              (url, {validator, abortTrigger}) async =>
                  fetchedValue(entry.value),
            ),
            publishedEventsFetcherProvider(entry.key).overrideWithValue(
              (url, {validator, abortTrigger}) async =>
                  const PublishedFileMissing(),
            ),
          ],
          // Saved copies in memory: a widget test has no path_provider.
          publishedFileCacheProvider.overrideWithValue(
            InMemoryPublishedFileCache(),
          ),
          // Run the pure viewer engine inline so widget tests can settle.
          publishedCatalogueQueryRunnerProvider.overrideWithValue(
            (catalogue, query) async =>
                PublishedQueryEngine.apply(catalogue, query),
          ),
        ],
        child: MaterialApp(
          home: LibraryBookmarksPage(
            publishedSiteOpener: opener ?? const PublishedSiteOpener(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => repo = _FakeRepo([]));

  testWidgets('empty state offers only the exact Add Bookmark action', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(SavedLibrariesView), findsOneWidget);
    expect(find.textContaining('No libraries saved yet.'), findsOneWidget);
    expect(
      find.textContaining('Tap "Add Bookmark" to save a library'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FloatingActionButton, 'Add Bookmark'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Refresh'), findsOneWidget);
    expect(find.text('Add member'), findsNothing);
    expect(find.textContaining('"Add member"'), findsNothing);
    expect(find.text('Add bookmark'), findsNothing);
  });

  testWidgets('shared rows render with their badges', (tester) async {
    repo.rows = [
      const NetworkLibrary(
        id: 1,
        siteUrl: 'https://m.github.io/x/',
        name: 'Member Library',
        fingerprint: fp,
        source: NetworkSource.card,
        isMember: true,
        memberVerified: true,
      ),
      const NetworkLibrary(
        id: 2,
        siteUrl: 'https://u.github.io/y/',
        name: 'Unverified One',
        source: NetworkSource.card,
        isMember: true,
      ),
      const NetworkLibrary(
        id: 3,
        siteUrl: 'https://c.github.io/z/',
        name: 'Clashing',
        fingerprint: fp,
        fetchStatus: FetchStatus.identityConflict,
      ),
      const NetworkLibrary(
        id: 4,
        siteUrl: 'https://d.github.io/w/',
        name: 'Confirmed Member',
        listedByHubUrl: 'https://m.github.io/x/',
        confirmedByMember: true,
      ),
      const NetworkLibrary(
        id: 5,
        siteUrl: 'https://e.github.io/v/',
        name: 'Claimed Only',
        listedByHubUrl: 'https://m.github.io/x/',
      ),
    ];
    await pumpPage(tester);
    expect(find.text('Member Library'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Identity conflict'), findsOneWidget);
    expect(find.text('https://m.github.io/x/'), findsOneWidget);

    final listScrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Unverified One'),
      150,
      scrollable: listScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Unverified'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Confirmed Member'),
      -150,
      scrollable: listScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirmed by member'), findsOneWidget);
  });

  group('add by URL (the exact "Add Bookmark" button)', () {
    testWidgets('a valid link saves a bookmark row and joins the list', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add Bookmark'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add a library by URL'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Link'),
        'https://new.github.io/lib/',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Name (optional)'),
        '  New Library  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        find.text('Library added. Tap Refresh to fetch its details.'),
        findsOneWidget,
      );
      expect(find.text('New Library'), findsOneWidget);
      final saved = repo.upserts.single;
      expect(saved.siteUrl, 'https://new.github.io/lib/');
      expect(saved.name, 'New Library');
      expect(saved.source, NetworkSource.bookmark);
    });

    testWidgets('a non-Pages link is refused inside the dialog', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add Bookmark'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Link'),
        'https://evil.example.com/',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Add a library by URL'), findsOneWidget);
      expect(
        find.textContaining('Enter a GitHub Pages (github.io)'),
        findsOneWidget,
      );
      expect(repo.upserts, isEmpty);
    });

    testWidgets('an already-saved link collapses with a clear message', (
      tester,
    ) async {
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: 'https://dup.github.io/x/'),
      ];
      await pumpPage(tester);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add Bookmark'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Link'),
        'https://dup.github.io/x/',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('That library is already saved.'), findsOneWidget);
      expect(repo.rows, hasLength(1));
    });
  });

  group('native viewer navigation (ADR 0015 V1)', () {
    PublishedCatalogue tinyCatalogue() => PublishedCatalogue(
      declaredSchemaVersion: 1,
      items: const [
        PublishedCatalogueItem(
          sourceIndex: 0,
          title: 'Published Book',
          kind: PublishedItemKind.book,
        ),
      ],
      periodicals: const [],
    );

    for (final source in NetworkSource.values) {
      testWidgets('a ${source.name} row opens the native viewer only', (
        tester,
      ) async {
        const rowUrl = 'https://a.github.io/one/';
        repo.rows = [
          NetworkLibrary(
            id: 1,
            siteUrl: rowUrl,
            name: 'First Library',
            source: source,
          ),
        ];
        final launcher = _RecordingLauncher();
        await pumpPage(
          tester,
          opener: PublishedSiteOpener(launch: launcher.launch),
          catalogues: {rowUrl: tinyCatalogue()},
        );

        await tester.tap(
          find.widgetWithText(NetworkLibraryTile, 'First Library'),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('Reload catalogue'), findsOneWidget);
        expect(find.text('Published Book'), findsOneWidget);
        expect(launcher.calls, isEmpty);

        await tester.tap(find.byTooltip('Open in browser'));
        await tester.pump();
        expect(launcher.calls, hasLength(1));
        expect(launcher.calls.single.toString(), rowUrl);
        expect(launcher.modes.single, LaunchMode.externalApplication);
      });
    }

    testWidgets('back returns to the standalone saved list', (tester) async {
      const rowUrl = 'https://a.github.io/one/';
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: rowUrl, name: 'First Library'),
      ];
      await pumpPage(tester, catalogues: {rowUrl: tinyCatalogue()});
      await tester.tap(
        find.widgetWithText(NetworkLibraryTile, 'First Library'),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reload catalogue'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reload catalogue'), findsNothing);
      expect(find.text('First Library'), findsOneWidget);
      expect(find.byType(LibraryBookmarksPage), findsOneWidget);
    });
  });
}

final class _RecordingLauncher {
  final List<Uri> calls = [];
  final List<LaunchMode> modes = [];

  Future<bool> launch(Uri url, LaunchMode mode) async {
    calls.add(url);
    modes.add(mode);
    return true;
  }
}

class _FakeRepo implements NetworkRepository {
  _FakeRepo(this.rows);

  List<NetworkLibrary> rows;
  final List<NetworkLibrary> upserts = [];

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    upserts.add(row);
    final index = rows.indexWhere((r) => r.siteUrl == row.siteUrl);
    if (index >= 0) {
      rows[index] = row.copyWith(id: rows[index].id);
      return right(rows[index]);
    }
    final saved = row.copyWith(id: rows.length + 1);
    rows.add(saved);
    return right(saved);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
