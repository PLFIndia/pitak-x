import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:pitaka/features/publish/presentation/widgets/library_share_card.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_card_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url = 'https://user.github.io/my-library/';

/// Hosts the card at its natural 1050×600 inside a large enough surface.
/// A `RepaintBoundary` with [key] wraps it when capture is under test.
Widget _host(
  LibraryShareCard card, {
  GlobalKey? key,
  TextScaler scaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    child: MediaQuery(
      data: MediaQueryData(textScaler: scaler),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: key == null ? card : RepaintBoundary(key: key, child: card),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpBig(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pump();
  }

  testWidgets('shows name, address, display url, QR and Pitak attribution', (
    tester,
  ) async {
    await pumpBig(
      tester,
      _host(
        const LibraryShareCard(
          style: ShareCardStyle.classic,
          libraryName: 'Riverside Community Library',
          address: '12 Lakeview Road, Kochi',
          url: _url,
        ),
      ),
    );

    expect(find.text('Riverside Community Library'), findsOneWidget);
    expect(find.text('12 Lakeview Road, Kochi'), findsOneWidget);
    expect(find.text('user.github.io/my-library'), findsOneWidget);
    expect(find.text('SCAN TO VISIT'), findsOneWidget);
    expect(find.text('Made with'), findsOneWidget);
    expect(find.text('Pitak'), findsOneWidget);
    expect(find.text('A community library app'), findsOneWidget);
    // The QR encodes the FULL url, not the shortened display text.
    final qr = tester.widget<QrView>(find.byType(QrView));
    expect(qr.data, _url);
  });

  testWidgets('blank name → "My Library" and a monogram tile', (tester) async {
    await pumpBig(
      tester,
      _host(
        const LibraryShareCard(
          style: ShareCardStyle.dark,
          libraryName: '',
          address: '',
          url: _url,
        ),
      ),
    );
    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('ML'), findsOneWidget); // monogram fallback, not Pitak
  });

  testWidgets('blank address omits the address line entirely', (tester) async {
    await pumpBig(
      tester,
      _host(
        const LibraryShareCard(
          style: ShareCardStyle.gradient,
          libraryName: 'Shelf',
          address: '   ',
          url: _url,
        ),
      ),
    );
    // Only the name, the url, the caption and the three footer strings.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(texts, isNot(contains('   ')));
    expect(texts, contains('Shelf'));
  });

  testWidgets('lays out at exactly 1050×600 in every style, no overflow', (
    tester,
  ) async {
    for (final style in ShareCardStyle.values) {
      await pumpBig(
        tester,
        _host(
          LibraryShareCard(
            style: style,
            libraryName:
                'A Very Long Library Name That Goes On And On '
                'And Keeps Going Past Two Lines Of Text For Sure',
            address: 'Line one of the address\nLine two\nLine three\nFour',
            url: 'https://${'x' * 120}.github.io/repo/',
          ),
        ),
      );
      final size = tester.getSize(find.byType(LibraryShareCard));
      expect(size, const Size(1050, 600), reason: '$style');
      expect(tester.takeException(), isNull, reason: '$style overflowed');
    }
  });

  testWidgets('ignores the device text scale (PNG must be deterministic)', (
    tester,
  ) async {
    Future<Size> nameSizeAt(TextScaler scaler) async {
      await pumpBig(
        tester,
        _host(
          const LibraryShareCard(
            style: ShareCardStyle.classic,
            libraryName: 'Shelf',
            address: '',
            url: _url,
          ),
          scaler: scaler,
        ),
      );
      return tester.getSize(find.text('Shelf'));
    }

    final normal = await nameSizeAt(TextScaler.noScaling);
    final huge = await nameSizeAt(const TextScaler.linear(2));
    expect(huge, normal);
  });

  testWidgets('captureBoundaryPng yields a 2100×1200 PNG', (tester) async {
    final key = GlobalKey();
    await pumpBig(
      tester,
      _host(
        const LibraryShareCard(
          style: ShareCardStyle.framed,
          libraryName: 'Shelf',
          address: 'Somewhere',
          url: _url,
        ),
        key: key,
      ),
    );

    // Rasterisation needs the real GPU-less engine path → runAsync.
    final bytes = await tester.runAsync(() => captureBoundaryPng(key));
    expect(bytes, isNotNull);
    // PNG signature.
    expect(bytes!.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    });
    expect(image!.width, 2100);
    expect(image.height, 1200);
    image.dispose();
  });

  testWidgets('captureBoundaryPng returns null for an unmounted key', (
    tester,
  ) async {
    await pumpBig(
      tester,
      _host(
        const LibraryShareCard(
          style: ShareCardStyle.classic,
          libraryName: 'Shelf',
          address: '',
          url: _url,
        ),
      ),
    );
    final bytes = await tester.runAsync(() => captureBoundaryPng(GlobalKey()));
    expect(bytes, isNull);
  });
}
