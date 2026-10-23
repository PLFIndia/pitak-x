/// The periodicals read models and the barcode router binding (plan S13).
///
/// N04 regression tests, same discipline as `derived_providers_test.dart`:
/// `periodicalById` / `periodicalByUid` must re-read their REAL inputs —
/// watching the repository object never fires — on BOTH mutation signals:
/// the series controller (form save, remove/restore, delete) and the
/// library controller (import, merge, restore rewrite periodicals without
/// going through the series controller). Every test keeps the derived
/// provider ALIVE with a listener; a bare `read` would dispose it and mask
/// staleness.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/route_scanned_barcode_use_case.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import '../../features/periodicals/application/periodical_fakes.dart';

void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;
  late ProviderContainer container;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
    container = ProviderContainer(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        clockProvider.overrideWithValue(() => 0),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Keeps [provider] alive for the test.
  void keepAlive(ProviderListenable<Object?> provider) {
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
  }

  group('periodicalById', () {
    test('resolves the row, and null for a missing id', () async {
      final series = periodicals.seed(const Periodical(title: 'Frontline'));
      keepAlive(periodicalByIdProvider(series.id));

      final found = await container.read(
        periodicalByIdProvider(series.id).future,
      );
      expect(found?.title, 'Frontline');
      expect(await container.read(periodicalByIdProvider(99).future), isNull);
    });

    test('follows a series mutation (the periodicals controller)', () async {
      final series = periodicals.seed(const Periodical(title: 'Old title'));
      keepAlive(periodicalByIdProvider(series.id));
      keepAlive(periodicalsControllerProvider);
      await container.read(periodicalsControllerProvider.future);
      expect(
        (await container.read(periodicalByIdProvider(series.id).future))!.title,
        'Old title',
      );

      periodicals.rows[series.id] = series.copyWith(title: 'New title');
      await container.read(periodicalsControllerProvider.notifier).refresh();

      expect(
        (await container.read(periodicalByIdProvider(series.id).future))!.title,
        'New title',
      );
    });

    test('follows a catalogue mutation (the library controller)', () async {
      final series = periodicals.seed(const Periodical(title: 'Old title'));
      keepAlive(periodicalByIdProvider(series.id));
      keepAlive(libraryControllerProvider);
      await container.read(libraryControllerProvider.future);
      expect(
        (await container.read(periodicalByIdProvider(series.id).future))!.title,
        'Old title',
      );

      // An import rewrote the series and fired only the library signal.
      periodicals.rows[series.id] = series.copyWith(title: 'Imported');
      await container.read(libraryControllerProvider.notifier).refresh();

      expect(
        (await container.read(periodicalByIdProvider(series.id).future))!.title,
        'Imported',
      );
    });

    test('a repository Left is thrown so the screen sees AsyncError', () async {
      periodicals.getByIdFailure = const StorageFailure('disk gone');
      keepAlive(periodicalByIdProvider(1));

      await expectLater(
        container.read(periodicalByIdProvider(1).future),
        throwsA(isA<StorageFailure>()),
      );
    });
  });

  group('periodicalByUid', () {
    test('resolves by the stable uid, and null for an unknown one', () async {
      final series = periodicals.seed(
        const Periodical(title: 'Frontline', periodicalUid: 'uid-fl'),
      );
      keepAlive(periodicalByUidProvider('uid-fl'));

      final found = await container.read(
        periodicalByUidProvider('uid-fl').future,
      );
      expect(found?.id, series.id);
      expect(
        await container.read(periodicalByUidProvider('nope').future),
        isNull,
      );
    });

    test('follows both mutation signals', () async {
      final series = periodicals.seed(
        const Periodical(title: 'v1', periodicalUid: 'uid-fl'),
      );
      keepAlive(periodicalByUidProvider('uid-fl'));
      keepAlive(periodicalsControllerProvider);
      keepAlive(libraryControllerProvider);
      await container.read(periodicalsControllerProvider.future);
      await container.read(libraryControllerProvider.future);
      Future<String> title() async => (await container.read(
        periodicalByUidProvider('uid-fl').future,
      ))!.title;
      expect(await title(), 'v1');

      periodicals.rows[series.id] = series.copyWith(title: 'v2');
      await container.read(periodicalsControllerProvider.notifier).refresh();
      expect(await title(), 'v2');

      periodicals.rows[series.id] = series.copyWith(title: 'v3');
      await container.read(libraryControllerProvider.notifier).refresh();
      expect(await title(), 'v3');
    });
  });

  group('routeScannedBarcodeUseCase', () {
    test('reaches the periodicals store for a 977 barcode', () async {
      final route = await container.read(
        routeScannedBarcodeUseCaseProvider.future,
      );
      final decision = await route('9770317847001');
      expect(decision, isA<AddPeriodicalByIssn>());
      expect(periodicals.calls, ['findByIssn:0317-8471']);
    });

    test('reaches the item store for an ISBN', () async {
      final route = await container.read(
        routeScannedBarcodeUseCaseProvider.future,
      );
      // `FakeItems` does not implement `findByIsbn`: reaching its
      // `noSuchMethod` proves the module handed the router the item store.
      await expectLater(route('9780441172719'), throwsUnimplementedError);
      expect(periodicals.calls, isEmpty);
    });
  });
}
