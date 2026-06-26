import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 1x1 transparent PNG — the smallest valid image Image.file can decode.
final _onePxPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _host(String coversDir, {required String? coverUrl}) {
  return ProviderScope(
    overrides: [coversDirProvider.overrideWith((ref) async => coversDir)],
    child: MaterialApp(
      home: Scaffold(
        body: BookCover(title: 'Hobbit', coverUrl: coverUrl),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('cover_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('null coverUrl shows the initial-letter placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_host(tmp.path, coverUrl: null));
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'remote https cover is NOT fetched when the toggle is off (default)',
    (tester) async {
      // loadRemoteCovers defaults off.
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        _host(tmp.path, coverUrl: 'https://example.com/c.jpg'),
      );
      await tester.pumpAndSettle();
      expect(find.text('H'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    },
  );

  testWidgets('remote https cover IS fetched when the toggle is on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'load_remote_covers': true});
    await tester.pumpWidget(
      _host(tmp.path, coverUrl: 'https://example.com/c.jpg'),
    );
    // Pump (not settle: the network fetch never completes in a test) and
    // assert the network widget mounted — i.e. the toggle gated correctly.
    await tester.pump();
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('http cover is never fetched even when the toggle is on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'load_remote_covers': true});
    await tester.pumpWidget(
      _host(tmp.path, coverUrl: 'http://example.com/c.jpg'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('H'), findsOneWidget);
  });

  testWidgets('missing local file falls back to the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_host(tmp.path, coverUrl: 'covers/nope.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
  });

  testWidgets('existing local cover renders an Image.file', (tester) async {
    File(p.join(tmp.path, 'real.png')).writeAsBytesSync(_onePxPng);
    await tester.pumpWidget(_host(tmp.path, coverUrl: 'covers/real.png'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('H'), findsNothing);
  });
}
