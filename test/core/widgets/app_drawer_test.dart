import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/core/widgets/app_drawer.dart';
import 'package:pitaka/features/guides/presentation/pages/guides_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodicals_page.dart';
import 'package:pitaka/features/publish/presentation/widgets/library_share_card.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';
import 'package:pitaka/features/share_apps/presentation/widgets/share_apps_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/periodicals/application/periodical_fakes.dart';

class _FakeShare implements FileShareService {
  String? sharedText;
  ShareOutcome outcome = ShareOutcome.success;

  @override
  Future<ShareOutcome> shareText(
    String text, {
    Rect? sharePositionOrigin,
  }) async {
    sharedText = text;
    return outcome;
  }

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();
}

Future<Widget> _app({String? publishedUrl, FileShareService? share}) async {
  // The drawer reads settings, which load from shared_preferences.
  return ProviderScope(
    overrides: [
      publishedSiteUrlProvider.overrideWith((ref) async => publishedUrl),
      if (share != null) fileShareServiceProvider.overrideWithValue(share),
    ],
    child: const MaterialApp(
      home: Scaffold(drawer: AppDrawer(), body: SizedBox()),
    ),
  );
}

void main() {
  testWidgets('header shows the library name when one is set', (tester) async {
    SharedPreferences.setMockInitialValues({
      'library_name': 'Indiranagar Books',
    });
    await tester.pumpWidget(await _app());
    // Open the drawer.
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Indiranagar Books'), findsOneWidget);
    expect(find.text('Pitak'), findsNothing);
  });

  testWidgets('header falls back to "Pitak" when no name is set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Pitak'), findsOneWidget);
  });

  testWidgets('lists the Library network destination below Wishlist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Wishlist'), findsOneWidget);
    // ADR 0012: the bookmarks destination became the library network.
    expect(find.text('Library network'), findsOneWidget);
    expect(find.text('Bookmarks'), findsNothing);
  });

  testWidgets('Magazines sits between Wishlist and Library network and opens '
      'the series list (ADR 0013 U2)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publishedSiteUrlProvider.overrideWith((ref) async => null),
          // The pushed page builds PeriodicalsController: its repository and
          // the pinned minute tick (the real 60 s timer would never settle).
          periodicalRepositoryProvider.overrideWith(
            (ref) async => FakePeriodicals(),
          ),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(
          home: Scaffold(drawer: AppDrawer(), body: SizedBox()),
        ),
      ),
    );
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    final magazinesY = tester.getTopLeft(find.text('Magazines')).dy;
    expect(tester.getTopLeft(find.text('Wishlist')).dy, lessThan(magazinesY));
    expect(
      tester.getTopLeft(find.text('Library network')).dy,
      greaterThan(magazinesY),
    );

    await tester.tap(find.text('Magazines'));
    await tester.pumpAndSettle();

    expect(find.byType(PeriodicalsPage), findsOneWidget);
    expect(find.text('No magazine titles yet'), findsOneWidget);
  });

  testWidgets('"Share Library Website" is hidden before the first publish', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Share Library Website'), findsNothing);
  });

  testWidgets(
    '"Share Library Website" closes the drawer and opens the share sheet '
    'for the published site URL',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final share = _FakeShare();
      await tester.pumpWidget(
        await _app(
          publishedUrl: 'https://user.github.io/my-library/',
          share: share,
        ),
      );
      tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share Library Website'));
      await tester.pumpAndSettle();

      // The drawer closed and the card/link sheet took over.
      expect(find.text('Share Library Website'), findsNothing);
      expect(find.byType(ShareLibrarySheet), findsOneWidget);
      expect(find.byType(LibraryShareCard), findsOneWidget);

      // The plain-link path still shares exactly the published URL.
      await tester.tap(find.text('Share link only'));
      await tester.pumpAndSettle();
      expect(share.sharedText, 'https://user.github.io/my-library/');
    },
  );

  testWidgets(
    'Share Apps sits immediately above Settings and shares only Pitak',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final share = _FakeShare();
      await tester.pumpWidget(await _app(share: share));
      tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      final shareTile = tester.getRect(
        find.ancestor(
          of: find.text('Share Apps'),
          matching: find.byType(ListTile),
        ),
      );
      final settingsTile = tester.getRect(
        find.ancestor(
          of: find.text('Settings'),
          matching: find.byType(ListTile),
        ),
      );
      expect(shareTile.bottom, closeTo(settingsTile.top, 0.01));

      await tester.tap(find.text('Share Apps'));
      await tester.pumpAndSettle();

      expect(find.byType(ShareAppsSheet), findsOneWidget);
      expect(find.text('Share Apps'), findsOneWidget);
      expect(find.text('Pitak'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ShareAppsSheet),
          matching: find.byType(ListTile),
        ),
        findsOneWidget,
        reason: 'Future apps must not appear as empty placeholder rows',
      );

      await tester.tap(find.byTooltip('Share Pitak'));
      await tester.pumpAndSettle();

      expect(
        share.sharedText,
        'https://play.google.com/store/apps/details?id=dev.khoj.pitaka',
      );
      expect(find.byType(ShareAppsSheet), findsOneWidget);
    },
  );

  testWidgets('Share Apps reports unavailable sharing with safe copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final share = _FakeShare()..outcome = ShareOutcome.unavailable;
    await tester.pumpWidget(await _app(share: share));
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share Apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share Pitak'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sharing is not available on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('Settings is pinned below the primary destinations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    // Settings sits lower on screen than every primary destination.
    final settingsY = tester.getTopLeft(find.text('Settings')).dy;
    for (final label in [
      'Borrowers vault',
      'Wishlist',
      'Library network',
      'How Pitak works',
    ]) {
      expect(
        tester.getTopLeft(find.text(label)).dy,
        lessThan(settingsY),
        reason: '$label should be above Settings',
      );
    }
  });

  testWidgets('"How Pitak works" is listed after Share and opens GuidesPage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      await _app(publishedUrl: 'https://user.github.io/my-library/'),
    );
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    // Position: below Share, above the pinned Settings.
    final guidesY = tester.getTopLeft(find.text('How Pitak works')).dy;
    expect(
      tester.getTopLeft(find.text('Share Library Website')).dy,
      lessThan(guidesY),
    );
    expect(tester.getTopLeft(find.text('Settings')).dy, greaterThan(guidesY));

    await tester.tap(find.text('How Pitak works'));
    await tester.pumpAndSettle();

    // The drawer closed and the guides index is on top (no providers needed).
    expect(find.byType(GuidesPage), findsOneWidget);
    expect(find.text('Put your catalogue online'), findsOneWidget);
    expect(find.text('Borrowers vault'), findsNothing);
  });
}
