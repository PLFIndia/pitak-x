import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/book_cover.dart';
import 'package:pitaka/features/library/application/remote_cover_materializer.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
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

/// Settings repo for the consent-flip tests: loads a fixed snapshot and
/// accepts the two writes the tests perform (cover toggle, theme).
class _SettingsRepo implements SettingsRepository {
  _SettingsRepo({required this.loadRemoteCovers});
  final bool loadRemoteCovers;

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(loadRemoteCovers: loadRemoteCovers);

  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async => right(unit);

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) async =>
      right(unit);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call');
}

const _allowListed = 'https://covers.openlibrary.org/b/id/1-L.jpg';
const _attacker = 'https://example.com/c.jpg';

Widget _host(
  String coversDir, {
  required String? coverUrl,
  required _RecordingMaterializer materializer,
  int? bookId,
  _SettingsRepo? settings,
}) {
  return ProviderScope(
    overrides: [
      coversDirProvider.overrideWith((ref) async => coversDir),
      remoteCoverMaterializerProvider.overrideWith(() => materializer),
      if (settings != null)
        settingsRepositoryProvider.overrideWith((ref) async => settings),
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

  testWidgets('D-2 (device-found, Session 13): a row already on screen asks '
      'again when consent flips OFF→ON — the list stays mounted under the '
      'Settings route, so no lifecycle hook fires and the toggle looked '
      'broken until a book was opened', (tester) async {
    final settings = _SettingsRepo(loadRemoteCovers: false);
    await tester.pumpWidget(
      _host(
        tmp.path,
        coverUrl: _allowListed,
        bookId: 7,
        materializer: materializer,
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();
    // First display asked (the scheduler drops it: consent is off).
    expect(materializer.requested, [7]);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookCover)),
    );
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    // The user flips the switch: the row must ask once more.
    await controller.setLoadRemoteCovers(enabled: true);
    await tester.pumpAndSettle();
    expect(materializer.requested, [7, 7], reason: 'OFF→ON re-asks');

    // Unrelated settings writes republish the whole snapshot but must not
    // re-ask (select narrows the listener to the consent bit).
    await controller.setThemeMode(AppThemeMode.dark);
    await tester.pumpAndSettle();
    expect(materializer.requested, [7, 7], reason: 'theme change is silent');

    // OFF has nothing new to show; ON again is a fresh edge.
    await controller.setLoadRemoteCovers(enabled: false);
    await tester.pumpAndSettle();
    expect(materializer.requested, [7, 7], reason: 'ON→OFF is silent');
    await controller.setLoadRemoteCovers(enabled: true);
    await tester.pumpAndSettle();
    expect(materializer.requested, [7, 7, 7]);
  });

  testWidgets('D-2: a recycled row follows its CURRENT book — after it '
      'switches to a local cover the consent flip is ignored; after it '
      'switches to a fetchable one the flip re-asks for the new id', (
    tester,
  ) async {
    final settings = _SettingsRepo(loadRemoteCovers: false);
    Widget host({required String? coverUrl, required int bookId}) => _host(
      tmp.path,
      coverUrl: coverUrl,
      bookId: bookId,
      materializer: materializer,
      settings: settings,
    );
    await tester.pumpWidget(host(coverUrl: _allowListed, bookId: 7));
    await tester.pumpAndSettle();
    expect(materializer.requested, [7]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookCover)),
    );
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);

    // Same State, recycled for a book with a LOCAL cover: nothing pending.
    await tester.pumpWidget(host(coverUrl: 'covers/x.jpg', bookId: 8));
    await tester.pumpAndSettle();
    await controller.setLoadRemoteCovers(enabled: true);
    await tester.pumpAndSettle();
    expect(materializer.requested, [7], reason: 'local cover: flip ignored');

    // Recycled again for a fetchable book while consent is ON: asks on the
    // recycle itself, and a later OFF→ON edge asks for THAT id, not 7.
    await tester.pumpWidget(host(coverUrl: _allowListed, bookId: 9));
    await tester.pumpAndSettle();
    expect(materializer.requested, [7, 9]);
    await controller.setLoadRemoteCovers(enabled: false);
    await controller.setLoadRemoteCovers(enabled: true);
    await tester.pumpAndSettle();
    expect(materializer.requested, [7, 9, 9]);
  });

  testWidgets('D-2: a row whose cover is NOT fetchable ignores the consent '
      'flip (attacker host / no bookId stay silent)', (tester) async {
    final settings = _SettingsRepo(loadRemoteCovers: false);
    await tester.pumpWidget(
      _host(
        tmp.path,
        coverUrl: _attacker,
        bookId: 7,
        materializer: materializer,
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BookCover)),
    );
    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setLoadRemoteCovers(enabled: true);
    await tester.pumpAndSettle();
    expect(materializer.requested, isEmpty);
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
