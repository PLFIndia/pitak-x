import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:pitaka/features/library/application/remote_cover_materializer.dart';
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

/// Records every materialise request the widget makes. The real notifier
/// does IO (fetch + file write + DB update); the widget's only contract is
/// "ask once for a fetchable cover", which is what these tests pin.
class _RecordingMaterializer extends RemoteCoverMaterializer {
  final List<int> requested = [];

  @override
  void request(int bookId) => requested.add(bookId);
}

const _allowListed = 'https://covers.openlibrary.org/b/id/1-L.jpg';
const _attacker = 'https://example.com/c.jpg';

Widget _host(
  String coversDir, {
  required String? coverUrl,
  required _RecordingMaterializer materializer,
  int? bookId,
}) {
  return ProviderScope(
    overrides: [
      coversDirProvider.overrideWith((ref) async => coversDir),
      remoteCoverMaterializerProvider.overrideWith(() => materializer),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: BookCover(title: 'Hobbit', coverUrl: coverUrl, bookId: bookId),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late _RecordingMaterializer materializer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cover_test');
    materializer = _RecordingMaterializer();
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('null coverUrl shows the initial-letter placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(tmp.path, coverUrl: null, materializer: materializer),
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(materializer.requested, isEmpty);
  });

  // M09: display is LOCAL-ONLY. A remote https ref is a pending download,
  // never an image the widget streams from the network itself.
  testWidgets('remote https cover renders the placeholder (never a network '
      'image), even for an allow-listed host', (tester) async {
    await tester.pumpWidget(
      _host(
        tmp.path,
        coverUrl: _allowListed,
        bookId: 7,
        materializer: materializer,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('M09: allow-listed https cover asks the materializer exactly '
      'once for this book', (tester) async {
    await tester.pumpWidget(
      _host(
        tmp.path,
        coverUrl: _allowListed,
        bookId: 7,
        materializer: materializer,
      ),
    );
    await tester.pumpAndSettle();
    // Extra rebuilds must not re-request (the notifier dedups too, but the
    // widget should not spam it on every frame).
    await tester.pump();
    await tester.pump();
    expect(materializer.requested, [7]);
  });

  testWidgets('M09: NON-allow-listed https host is never requested, even '
      'though it is https', (tester) async {
    // The old widget streamed this straight into CachedNetworkImage once the
    // toggle was on — the reviewer's M09 finding.
    SharedPreferences.setMockInitialValues({'load_remote_covers': true});
    await tester.pumpWidget(
      _host(
        tmp.path,
        coverUrl: _attacker,
        bookId: 7,
        materializer: materializer,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(materializer.requested, isEmpty);
  });

  testWidgets('http cover is never requested', (tester) async {
    await tester.pumpWidget(
      _host(
        tmp.path,
        coverUrl: 'http://covers.openlibrary.org/b/id/1-L.jpg',
        bookId: 7,
        materializer: materializer,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(materializer.requested, isEmpty);
  });

  testWidgets('remote cover without a bookId cannot be materialised and just '
      'shows the placeholder', (tester) async {
    await tester.pumpWidget(
      _host(tmp.path, coverUrl: _allowListed, materializer: materializer),
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(materializer.requested, isEmpty);
  });

  testWidgets('missing local file falls back to the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(tmp.path, coverUrl: 'covers/nope.jpg', materializer: materializer),
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    expect(materializer.requested, isEmpty);
  });

  testWidgets('existing local cover renders an Image.file', (tester) async {
    File(p.join(tmp.path, 'real.png')).writeAsBytesSync(_onePxPng);
    await tester.pumpWidget(
      _host(tmp.path, coverUrl: 'covers/real.png', materializer: materializer),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('H'), findsNothing);
    expect(materializer.requested, isEmpty);
  });
}
