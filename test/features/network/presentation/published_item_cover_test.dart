import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/presentation/widgets/published_item_cover.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// The cover slot's security shape (ADR 0015 V11, viewer plan S5): no request
/// without explicit consent, no request for an unsafe reference, and only
/// downscaled in-memory bytes ever reach the image widget.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  final jpeg = img.encodeJpg(
    img.Image(width: 4, height: 6)..clear(img.ColorRgb8(10, 20, 30)),
  );

  PublishedCatalogueItem itemWith(String? coverUrl) => PublishedCatalogueItem(
    sourceIndex: 0,
    title: 'A Book',
    kind: PublishedItemKind.book,
    coverUrl: coverUrl,
  );

  late _FakeFetcher fetch;

  setUp(() {
    fetch = _FakeFetcher(jpeg);
  });

  Future<ProviderContainer> pumpCover(
    WidgetTester tester, {
    required String? coverUrl,
    bool consent = true,
    bool settingsFail = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        publishedCoverFetcherProvider(site).overrideWithValue(fetch.call),
        settingsRepositoryProvider.overrideWith(
          (ref) async => settingsFail
              ? _FailingSettings()
              : _SettingsRepo(loadRemoteCovers: consent),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: PublishedItemCover(
                item: itemWith(coverUrl),
                siteUrl: site,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('no cover reference means no request, just a placeholder', (
    tester,
  ) async {
    await pumpCover(tester, coverUrl: null);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(fetch.calls, isEmpty);
  });

  testWidgets('an unsafe reference never produces a request', (tester) async {
    await pumpCover(tester, coverUrl: 'https://evil.example/a.jpg');
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(fetch.calls, isEmpty);
  });

  testWidgets('consent OFF shows a placeholder and makes no request', (
    tester,
  ) async {
    await pumpCover(tester, coverUrl: 'covers/a.jpg', consent: false);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(fetch.calls, isEmpty);
  });

  testWidgets('failed/unknown settings fail closed', (tester) async {
    await pumpCover(tester, coverUrl: 'covers/a.jpg', settingsFail: true);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(fetch.calls, isEmpty);
  });

  testWidgets('consent ON shows an in-memory image, never a network image', (
    tester,
  ) async {
    await pumpCover(tester, coverUrl: 'covers/a.jpg');
    expect(fetch.calls, hasLength(1));
    expect(fetch.calls.single, isA<SameSiteCoverRequest>());

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    expect(images.single.image, isA<MemoryImage>());
    expect(images.single.image, isNot(isA<NetworkImage>()));
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
  });

  testWidgets('a third-party cover also needs consent', (tester) async {
    const absolute = 'https://covers.openlibrary.org/b/id/1-L.jpg';
    await pumpCover(tester, coverUrl: absolute, consent: false);
    expect(fetch.calls, isEmpty);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('flipping consent OFF→ON re-requests the visible cover', (
    tester,
  ) async {
    final container = await pumpCover(
      tester,
      coverUrl: 'covers/a.jpg',
      consent: false,
    );
    expect(fetch.calls, isEmpty);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .setLoadRemoteCovers(enabled: true);
    await tester.pumpAndSettle();

    expect(fetch.calls, hasLength(1));
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    expect(images.single.image, isA<MemoryImage>());
  });

  testWidgets('undecodable cached bytes degrade to the placeholder', (
    tester,
  ) async {
    fetch = _FakeFetcher(const [1, 2, 3, 4]);
    await pumpCover(tester, coverUrl: 'covers/a.jpg');
    await tester.pumpAndSettle();
    // Image.memory's errorBuilder takes over; no exception escapes.
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });
}

/// A cover port returning fixed bytes.
final class _FakeFetcher {
  _FakeFetcher(this.bytes);

  final List<int> bytes;
  final List<PublishedCoverRequest> calls = [];

  Future<Uint8List?> call(
    PublishedCoverRequest request, {
    Future<void>? abortTrigger,
  }) async {
    calls.add(request);
    return Uint8List.fromList(bytes);
  }
}

/// A settings repository with only the cover switch meaningful.
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

/// A settings repository that never loads.
class _FailingSettings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => throw StateError('settings unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call');
}
