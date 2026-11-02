import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/presentation/widgets/availability_lifecycle_relay.dart';
import 'package:pitaka/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal repo so the app shell can boot without a real database in tests
/// (the full Library behaviour is covered in library_page_test.dart).
class _EmptyRepo implements CatalogueItemRepository {
  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(const []);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <CatalogueItem>[]
        : (await getAll()).getOrElse((_) => const []);
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

/// Stands in for the availability lane: counts how `main.dart` reaches it
/// without touching storage or the network.
class _CountingLane extends AvailabilityAutoPublisher {
  int builds = 0;
  int resumes = 0;

  @override
  AvailabilityLaneView build() {
    builds++;
    return AvailabilityLaneView.starting;
  }

  @override
  Future<void> resumed() async => resumes++;
}

void main() {
  group('the availability lane starts with the app (plan S8)', () {
    Future<_CountingLane> boot(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final lane = _CountingLane();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogueItemRepositoryProvider.overrideWith(
              (ref) async => _EmptyRepo(),
            ),
            availabilityAutoPublisherProvider.overrideWith(() => lane),
          ],
          child: const PitakaApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2)); // the splash timer
      await tester.pumpAndSettle();
      return lane;
    }

    testWidgets('built once at app start, before any publish screen', (
      tester,
    ) async {
      final lane = await boot(tester);

      expect(find.text('Library'), findsOneWidget);
      expect(lane.builds, 1, reason: 'a loan on any screen is published');
    });

    testWidgets('the relay sits above MaterialApp and forwards a resume', (
      tester,
    ) async {
      final lane = await boot(tester);
      expect(
        find.ancestor(
          of: find.byType(MaterialApp),
          matching: find.byType(AvailabilityLifecycleRelay),
        ),
        findsOneWidget,
      );

      // The legal round trip (the app's own AppLifecycleListener asserts
      // every step): background, then foreground again.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();

      expect(lane.resumes, 1);
      expect(lane.builds, 1, reason: 'keepAlive: never rebuilt by a resume');
    });
  });

  testWidgets('app boots to the Library screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _EmptyRepo(),
          ),
        ],
        child: const PitakaApp(),
      ),
    );
    // The app now opens on a ~1s branding splash before the Library; advance
    // past the splash timer (the biometric gate is off by default).
    await tester.pump(); // first frame (splash)
    await tester.pump(const Duration(seconds: 2)); // fire the splash timer
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
