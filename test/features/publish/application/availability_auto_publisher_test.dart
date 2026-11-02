import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_runner.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_ids_changes.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

import '../support/availability_lane_fakes.dart';
import '../support/cloudflare_s8_fakes.dart';
import '../support/github_lane_fakes.dart';

/// The lane's Riverpod shell (plan C.4 "Shape"): it reads its inputs from
/// providers, never starts before activation (plan S8), and forwards every
/// trigger. `ProviderContainer` overrides only — no real storage or network.
void main() {
  final target = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'kadugodi-library',
    accountSubdomain: 'kadugodi',
  )!;
  const base = 1761984000000;
  late List<CatalogueItem> items;

  late MemoryAvailabilityLaneStore store;
  late _Settings settings;
  late List<AvailabilityUpdate> sent;
  late AvailabilityPublishResult Function() answer;
  late int runnerBuilds;
  late _PublishResults? publishResults;

  setUp(() {
    items = const [CatalogueItem(id: 1, title: 'One copy')];
    store = MemoryAvailabilityLaneStore();
    settings = _Settings();
    sent = [];
    answer = () => const AvailabilityLive(acceptedAt: base);
    runnerBuilds = 0;
    publishResults = null;
  });

  ProviderContainer container(
    FakeAsync fake, {
    required bool activated,
    bool laneStoreFails = false,
  }) {
    final queue = SerialOpQueue();
    final c = ProviderContainer(
      overrides: [
        availabilityLaneActivatedProvider.overrideWithValue(activated),
        clockProvider.overrideWithValue(
          () => base + fake.elapsed.inMilliseconds,
        ),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        catalogueItemRepositoryProvider.overrideWith(
          (ref) async => _Catalogue(() => items),
        ),
        libraryControllerProvider.overrideWith(_Library.new),
        publishControllerProvider.overrideWith(() {
          final results = _PublishResults();
          publishResults = results;
          return results;
        }),
        activeLoanCountsProvider.overrideWith((ref) => ref.watch(_counts)),
        availabilityLaneRepositoryProvider.overrideWith(
          (ref) async => laneStoreFails
              ? throw StateError('no prefs')
              : AvailabilityLaneRepository(store),
        ),
        publishManifestStoreProvider.overrideWith(
          (ref) async => LaneMemManifest(),
        ),
        availabilityItemKeysProvider.overrideWithValue(
          const PublishItemKeys(_Salt()),
        ),
        availabilityPublishRunnerProvider.overrideWith((ref) async {
          runnerBuilds++;
          return AvailabilityPublishRunner(
            queue: queue,
            resolveTarget: () async => Right(target),
            gitHub: ({required target, required update}) async =>
                fail('not a GitHub site'),
            cloudflare: ({required target, required update}) async {
              sent.add(update);
              return answer();
            },
            gitHubRecord: LaneMemManifest(),
            cloudflareRecord: InMemoryCloudflareManifestStore(),
          );
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  AvailabilityLaneStatus statusOf(ProviderContainer c) =>
      c.read(availabilityAutoPublisherProvider).status;

  test('not activated: the lane never starts and builds nothing (plan S8)', () {
    fakeAsync((fake) {
      final c = container(fake, activated: false)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(const Duration(minutes: 5));

      expect(statusOf(c), isA<AvailabilityLaneStarting>());
      expect(runnerBuilds, 0);
      expect(sent, isEmpty);
      expect(store.writes, isEmpty);
    });
  });

  test('activated: a loan is saved and published 20 s later', () {
    fakeAsync((fake) {
      final c = container(fake, activated: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {})
        ..read(settingsControllerProvider);
      fake.elapse(Duration.zero);
      expect(
        (statusOf(c) as AvailabilityLaneNotReady).reason,
        AvailabilityLaneMessages.unlockVault,
      );

      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(Duration.zero);
      expect(store.saved!.pending!.keys, hasLength(1));
      fake.elapse(const Duration(seconds: 20));

      expect(sent.single, isA<AvailabilityWrite>());
      expect(statusOf(c), isA<AvailabilityLaneUpToDate>());
      expect(c.read(availabilityAutoPublisherProvider).noticeDue, isTrue);

      c.read(availabilityAutoPublisherProvider.notifier).dismissNotice();
      fake.elapse(Duration.zero);
      expect(c.read(availabilityAutoPublisherProvider).noticeDue, isFalse);
    });
  });

  test('switching off in Settings publishes the removal', () {
    fakeAsync((fake) {
      final c = container(fake, activated: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(const Duration(seconds: 21));
      expect(sent, hasLength(1));

      c
          .read(settingsControllerProvider.notifier)
          .setAutoPublishAvailability(enabled: false)
          .ignore();
      fake.elapse(const Duration(seconds: 1));

      // The runner's local check finds no recorded file on this fake
      // Cloudflare record, so nothing goes over the network (R13).
      expect(sent, hasLength(1));
      expect(statusOf(c), isA<AvailabilityLaneOff>());
      expect(store.saved!.holdsNoSnapshots, isTrue);
    });
  });

  test('a successful catalogue publish retries a "not ready" set', () {
    fakeAsync((fake) {
      answer = () => const AvailabilityNotReady(
        AvailabilityPublishMessages.catalogueNotKeyed,
      );
      final c = container(fake, activated: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(const Duration(seconds: 21));
      expect(statusOf(c), isA<AvailabilityLaneNotReady>());

      answer = () => const AvailabilityLive(acceptedAt: base);
      publishResults!.succeed();
      fake.elapse(const Duration(seconds: 1));

      expect(sent, hasLength(2));
      expect(statusOf(c), isA<AvailabilityLaneUpToDate>());
    });
  });

  test('a restore signal forgets the saved sets (plan J9)', () {
    fakeAsync((fake) {
      answer = () => const AvailabilityPending('No connection.');
      final c = container(fake, activated: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(const Duration(seconds: 21));
      expect(store.saved!.pending, isNotNull);

      c.read(_counts.notifier).state = null;
      c.read(catalogueIdsChangesProvider.notifier).changed();
      fake.elapse(const Duration(hours: 1));

      expect(store.saved!.holdsNoSnapshots, isTrue);
      expect(sent, hasLength(1), reason: 'the old set never goes out');
    });
  });

  test('a catalogue change re-reads the items (the library signal)', () {
    fakeAsync((fake) {
      final c = container(fake, activated: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {2: 1}; // id 2 is not in the catalogue
      fake.elapse(const Duration(seconds: 21));
      expect((sent.single as AvailabilityWrite).snapshot.keys, isEmpty);

      items = const [
        CatalogueItem(id: 1, title: 'One copy'),
        CatalogueItem(id: 2, title: 'Just added'),
      ];
      c.invalidate(libraryControllerProvider);
      fake.elapse(const Duration(seconds: 21));

      expect((sent.last as AvailabilityWrite).snapshot.keys, hasLength(1));
    });
  });

  test('a lane that cannot start stays quiet (fail closed)', () {
    fakeAsync((fake) {
      final c = container(fake, activated: true, laneStoreFails: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(const Duration(minutes: 5));

      expect(statusOf(c), isA<AvailabilityLaneStarting>());
      expect(sent, isEmpty);
      c.read(availabilityAutoPublisherProvider.notifier).publishNow();
      fake.elapse(Duration.zero);
      expect(sent, isEmpty);
    });
  });

  test('the button and a resume reach the lane', () {
    fakeAsync((fake) {
      answer = () => const AvailabilityPending('No connection.');
      final c = container(fake, activated: true)
        ..listen(availabilityAutoPublisherProvider, (_, _) {});
      c.read(_counts.notifier).state = {1: 1};
      fake.elapse(const Duration(seconds: 21));
      expect(sent, hasLength(1));

      c.read(availabilityAutoPublisherProvider.notifier).resumed();
      fake.elapse(Duration.zero);
      expect(sent, hasLength(2), reason: 'a resume retries at once');

      c.read(availabilityAutoPublisherProvider.notifier).publishNow();
      fake.elapse(Duration.zero);
      expect(sent, hasLength(3));
    });
  });
}

/// The test's loan counts; null = vault locked.
final _counts = StateProvider<Map<int, int>?>((ref) => null);

final class _Salt implements PublishCoverSaltStore {
  const _Salt();

  @override
  Future<List<int>> salt() async => ascii.encode('salt-1234567890');
}

final class _Catalogue implements CatalogueItemRepository {
  _Catalogue(this.items);

  final List<CatalogueItem> Function() items;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      Right(items());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _Library extends LibraryController {
  @override
  FutureOr<LibraryWindow> build() =>
      const LibraryWindow(books: [], hasMore: false);
}

class _PublishResults extends PublishController {
  @override
  FutureOr<PublishResult?> build() => null;

  void succeed() => state = const AsyncData(
    PublishSuccess(pagesUrl: 'https://example.org/', uploadedPaths: []),
  );
}

final class _Settings implements SettingsRepository {
  AppSettings current = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<Either<Failure, Unit>> setAutoPublishAvailability({
    required bool enabled,
  }) async {
    current = current.copyWith(autoPublishAvailability: enabled);
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
