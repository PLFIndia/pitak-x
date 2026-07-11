import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/core/widgets/app_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShare implements FileShareService {
  String? sharedText;
  @override
  Future<ShareOutcome> shareText(
    String text, {
    Rect? sharePositionOrigin,
  }) async {
    sharedText = text;
    return ShareOutcome.success;
  }

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
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

  testWidgets('lists the Bookmarks destination below Wishlist', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
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

  testWidgets('"Share Library Website" shares the published site URL', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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

    expect(share.sharedText, 'https://user.github.io/my-library/');
    // The drawer closed on tap.
    expect(find.text('Share Library Website'), findsNothing);
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
    for (final label in ['Borrowers vault', 'Wishlist', 'Bookmarks']) {
      expect(
        tester.getTopLeft(find.text(label)).dy,
        lessThan(settingsY),
        reason: '$label should be above Settings',
      );
    }
  });
}
