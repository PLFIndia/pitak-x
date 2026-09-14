import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_share_card_style_store.dart';
import 'package:pitaka/features/publish/presentation/widgets/library_share_card.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url = 'https://user.github.io/my-library/';

class _FakeShare implements FileShareService {
  String? sharedText;
  Uint8List? sharedBytes;
  String? sharedFileName;
  String? sharedMime;

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
  }) async {
    sharedBytes = bytes;
    sharedFileName = fileName;
    sharedMime = mimeType;
    return ShareOutcome.success;
  }
}

/// A style store whose save always fails (the "applied but not saved" path).
class _FailingStyleStore implements ShareCardStyleStore {
  @override
  Future<ShareCardStyle> load() async => ShareCardStyle.classic;
  @override
  Future<Either<Failure, Unit>> save(ShareCardStyle style) async =>
      left(const StorageFailure('nope'));
}

/// A page with a button that opens the sheet — exercises the real
/// `showShareLibrarySheet` route, not just the body widget.
Widget _app(FileShareService share, {ShareCardStyleStore? styleStore}) {
  return ProviderScope(
    overrides: [
      fileShareServiceProvider.overrideWithValue(share),
      if (styleStore != null)
        shareCardStyleStoreProvider.overrideWith((_) async => styleStore),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showShareLibrarySheet(context, url: _url),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'library_name': 'Riverside Community Library',
      'publish_contact_address': '12 Lakeview Road, Kochi',
    }),
  );

  testWidgets('shows a live preview and the four style swatches', (
    tester,
  ) async {
    await _open(tester, _app(_FakeShare()));

    expect(find.text('Share your library'), findsOneWidget);
    expect(find.byType(LibraryShareCard), findsOneWidget);
    for (final style in ShareCardStyle.values) {
      expect(find.text(style.label), findsOneWidget);
    }
    // Preview carries the user's data from settings.
    expect(find.text('Riverside Community Library'), findsOneWidget);
    expect(find.text('12 Lakeview Road, Kochi'), findsOneWidget);
    // Default style is classic.
    final card = tester.widget<LibraryShareCard>(find.byType(LibraryShareCard));
    expect(card.style, ShareCardStyle.classic);
    expect(card.url, _url);
  });

  testWidgets('tapping a swatch restyles the preview and remembers it', (
    tester,
  ) async {
    await _open(tester, _app(_FakeShare()));

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final card = tester.widget<LibraryShareCard>(find.byType(LibraryShareCard));
    expect(card.style, ShareCardStyle.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsShareCardStyleStore.key), 'dark');
  });

  testWidgets('reopens with the remembered style', (tester) async {
    SharedPreferences.setMockInitialValues({
      PrefsShareCardStyleStore.key: 'framed',
    });
    await _open(tester, _app(_FakeShare()));
    final card = tester.widget<LibraryShareCard>(find.byType(LibraryShareCard));
    expect(card.style, ShareCardStyle.framed);
  });

  testWidgets('a failed style save is reported but the style still applies', (
    tester,
  ) async {
    await _open(tester, _app(_FakeShare(), styleStore: _FailingStyleStore()));

    await tester.tap(find.text('Gradient'));
    await tester.pumpAndSettle();

    final card = tester.widget<LibraryShareCard>(find.byType(LibraryShareCard));
    expect(card.style, ShareCardStyle.gradient);
    expect(find.text('Style applied, but could not be saved.'), findsOneWidget);
  });

  testWidgets('"Share card" shares a PNG named after the library and closes', (
    tester,
  ) async {
    final share = _FakeShare();
    await _open(tester, _app(share));

    // Rasterisation runs on the engine → runAsync, then let the pop settle.
    await tester.runAsync(() async {
      await tester.tap(find.text('Share card'));
      await tester.pump();
      // Give the toImage/PNG-encode futures time to resolve.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(share.sharedText, isNull);
    expect(share.sharedMime, 'image/png');
    expect(share.sharedFileName, 'riverside-community-library-card.png');
    expect(share.sharedBytes, isNotNull);
    expect(share.sharedBytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // The sheet closed after a successful share.
    expect(find.text('Share your library'), findsNothing);
  });

  testWidgets('"Share link only" shares the plain URL and closes', (
    tester,
  ) async {
    final share = _FakeShare();
    await _open(tester, _app(share));

    await tester.tap(find.text('Share link only'));
    await tester.pumpAndSettle();

    expect(share.sharedText, _url);
    expect(share.sharedBytes, isNull);
    expect(find.text('Share your library'), findsNothing);
  });
}
