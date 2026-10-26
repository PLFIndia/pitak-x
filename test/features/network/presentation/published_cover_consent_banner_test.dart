import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/presentation/widgets/published_cover_consent_banner.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

void main() {
  PublishedCatalogue catalogue({bool withCover = true}) => PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: [
      PublishedCatalogueItem(
        sourceIndex: 0,
        title: 'A Book',
        kind: PublishedItemKind.book,
        coverUrl: withCover ? 'covers/a.jpg' : null,
      ),
    ],
    periodicals: const [],
  );

  ProviderContainer makeContainer(
    Future<SettingsRepository> Function() repository,
  ) {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWith((ref) => repository()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpBanner(
    WidgetTester tester,
    ProviderContainer container,
    PublishedCatalogue catalogue,
  ) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PublishedCoverConsentBanner(catalogue: catalogue),
          ),
        ),
      ),
    );
  }

  void expectHidden() {
    expect(find.text('Load covers'), findsNothing);
    expect(find.textContaining('Cover images are off'), findsNothing);
  }

  testWidgets('hidden when consent is already on', (tester) async {
    final container = makeContainer(
      () async => _SettingsRepo(loadRemoteCovers: true),
    );
    await pumpBanner(tester, container, catalogue());
    await tester.pumpAndSettle();

    expectHidden();
  });

  testWidgets('hidden when the loaded catalogue has no covers', (tester) async {
    final container = makeContainer(
      () async => _SettingsRepo(loadRemoteCovers: false),
    );
    await pumpBanner(tester, container, catalogue(withCover: false));
    await tester.pumpAndSettle();

    expectHidden();
  });

  testWidgets('hidden while settings are loading', (tester) async {
    final pending = Completer<SettingsRepository>();
    final container = makeContainer(() => pending.future);
    await pumpBanner(tester, container, catalogue());
    await tester.pump();

    expectHidden();
  });

  testWidgets('hidden when settings fail to load', (tester) async {
    final container = makeContainer(
      () async => throw StateError('settings unavailable'),
    );
    await pumpBanner(tester, container, catalogue());
    await tester.pumpAndSettle();

    expectHidden();
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible with covers and consent off', (tester) async {
    final container = makeContainer(
      () async => _SettingsRepo(loadRemoteCovers: false),
    );
    await pumpBanner(tester, container, catalogue());
    await tester.pumpAndSettle();

    expect(find.textContaining('Cover images are off'), findsOneWidget);
    expect(find.textContaining('approved cover services'), findsOneWidget);
    expect(find.textContaining('stay in memory'), findsOneWidget);
    expect(find.text('Load covers'), findsOneWidget);
  });

  testWidgets('a series cover also makes the banner visible', (tester) async {
    final container = makeContainer(
      () async => _SettingsRepo(loadRemoteCovers: false),
    );
    await pumpBanner(
      tester,
      container,
      PublishedCatalogue(
        declaredSchemaVersion: 1,
        items: const [],
        periodicals: const [
          PublishedPeriodical(
            periodicalUid: 'series-1',
            title: 'A Series',
            coverUrl: 'covers/series.jpg',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Load covers'), findsOneWidget);
  });

  testWidgets('Load covers persists the setting and hides the banner', (
    tester,
  ) async {
    final repository = _SettingsRepo(loadRemoteCovers: false);
    final container = makeContainer(() async => repository);
    await pumpBanner(tester, container, catalogue());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load covers'));
    await tester.pumpAndSettle();

    expect(repository.writeCount, 1);
    expect(repository.loadRemoteCovers, isTrue);
    expect((await repository.load()).loadRemoteCovers, isTrue);
    expectHidden();
  });

  testWidgets('a failed preference write keeps the opt-in available to retry', (
    tester,
  ) async {
    final repository = _SettingsRepo(loadRemoteCovers: false)
      ..failWrites = true;
    final container = makeContainer(() async => repository);
    await pumpBanner(tester, container, catalogue());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load covers'));
    await tester.pumpAndSettle();

    expect(repository.writeCount, 1);
    expect(repository.loadRemoteCovers, isFalse);
    expect(find.text('Load covers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A small settings fake whose toggle really survives a subsequent [load].
final class _SettingsRepo implements SettingsRepository {
  _SettingsRepo({required this.loadRemoteCovers});

  bool loadRemoteCovers;
  bool failWrites = false;
  int writeCount = 0;

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(loadRemoteCovers: loadRemoteCovers);

  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({
    required bool enabled,
  }) async {
    writeCount++;
    if (failWrites) return left(const StorageFailure('write failed'));
    loadRemoteCovers = enabled;
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected settings call: $invocation');
}
