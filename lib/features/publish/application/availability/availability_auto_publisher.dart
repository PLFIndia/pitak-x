/// The availability lane as a Riverpod notifier (application layer;
/// ADR 0019, plan C.4 "Shape").
///
/// A thin shell: it reads the lane's inputs from providers, forwards changes
/// and triggers to [AvailabilityLane] (where every decision lives), and
/// exposes the lane's [AvailabilityLaneView] to the status row.
///
/// keepAlive (justification, AGENTS.md §4): the lane's timers and its pending
/// set must outlive every screen. A loan made on the borrower screen must
/// still be published 20 s later, after the user has moved on; with
/// auto-dispose the timer would die with the last listening widget.
///
/// **Started at app start** (plan S8): `PitakaApp` in `main.dart` listens to
/// this provider, which builds it once (plan C.4 "Start"). It starts no lane
/// while `availabilityLaneActivatedProvider` is false (the build's kill
/// switch, plan A.6 #77).
///
/// The catalogue is read only while loan counts are known (plan S8, A.6
/// #78): with the vault locked no set can be computed, so reading every row
/// at app start would be wasted work on a large library.
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/application/availability/catalogue_ids_changes.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/application/site/publish_host_state_repository.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'availability_auto_publisher.g.dart';

/// Owns the one [AvailabilityLane] of this app run.
@Riverpod(keepAlive: true)
class AvailabilityAutoPublisher extends _$AvailabilityAutoPublisher {
  AvailabilityLane? _lane;

  /// The catalogue as last read; refreshed only when the library changes,
  /// so a loan (counts only) does not re-read every row.
  List<CatalogueItem>? _items;
  bool _itemsStale = true;

  @override
  AvailabilityLaneView build() {
    // Listeners first, synchronously; they forward only once the lane exists.
    ref
      ..listen(
        settingsControllerProvider.select(
          (settings) => settings.valueOrNull?.autoPublishAvailability,
        ),
        (_, _) => _forward(),
      )
      ..listen(activeLoanCountsProvider, (_, _) => _forward())
      // The library list's controller is the catalogue mutation signal (the
      // same signal the vault read models use, N04).
      ..listen(libraryControllerProvider, (_, _) {
        _itemsStale = true;
        _forward();
      })
      // A catalogue publish (or a reviewed repair) may make the site ready.
      ..listen(publishControllerProvider, (_, next) {
        if (next.valueOrNull is PublishSuccess) {
          unawaited(_lane?.sitePublished());
        }
      })
      // A restore or an overwrite merge changed what item ids name (J9).
      ..listen(catalogueIdsChangesProvider, (_, _) {
        _itemsStale = true;
        final lane = _lane;
        // Inputs read AFTER the change: the old ones name the old items.
        if (lane != null) unawaited(_inputs().then(lane.libraryReplaced));
      })
      ..onDispose(() => _lane?.dispose());
    if (ref.read(availabilityLaneActivatedProvider)) unawaited(_start());
    return AvailabilityLaneView.starting;
  }

  /// **Update availability now**.
  Future<void> publishNow() async => _lane?.publishNow();

  /// Hides the one-time notice for good.
  Future<void> dismissNotice() async => _lane?.dismissNotice();

  /// The app returned to the foreground (`AvailabilityLifecycleRelay`).
  Future<void> resumed() async => _lane?.resumed();

  Future<void> _start() async {
    try {
      final queue = ref.read(publishOperationQueueProvider);
      final itemKeys = ref.read(availabilityItemKeysProvider);
      // One deferred check per lane, cancelled with it (ADR 0019
      // Decision 10). It upgrades a GitHub commit to `live` outside the
      // queue and records the verified address only after proof (R33).
      final deferred = DeferredPublishVerification(
        reader: ref.read(publishedSiteReadVerifierProvider),
        manifest: await ref.read(publishManifestStoreProvider.future),
        hostState: LazyPublishHostStateRecorder(
          () => ref.read(publishHostStateRepositoryProvider.future),
        ),
        queue: queue,
      );
      ref.onDispose(deferred.cancel);
      final lane = AvailabilityLane(
        repository: await ref.read(availabilityLaneRepositoryProvider.future),
        // Inside the publish queue: every salt read (and its one-time
        // generation) happens there, so the lane and a catalogue publish can
        // never generate two different salts.
        keysFor: (ids) => queue.enqueue(() => itemKeys.keysFor(ids)),
        publish: (update) async =>
            (await ref.read(availabilityPublishRunnerProvider.future))(update),
        currentTarget: () async => (await ref.read(
          availabilityPublishRunnerProvider.future,
        )).currentTarget(),
        prove: deferred.run,
        onView: (view) => state = view,
        clock: ref.read(clockProvider),
      );
      _lane = lane;
      await lane.start(await _inputs());
    } on Object catch (error) {
      // Fail closed: no lane, nothing published. Type only (AGENTS §6.2).
      appLog('availability lane did not start: ${error.runtimeType}');
    }
  }

  void _forward() {
    final lane = _lane;
    if (lane == null) return;
    unawaited(_inputs().then(lane.update));
  }

  Future<AvailabilityLaneInputs> _inputs() async {
    final counts = ref.read(activeLoanCountsProvider);
    // Unknown counts (vault locked) cannot compute a set, so the items would
    // not be used: they are read when the counts become known (the counts
    // listener forwards then). Until that first read they stay null, which
    // the lane already treats as "unknown" (AV5).
    if (counts != null && _itemsStale) {
      _itemsStale = false;
      final repository = await ref.read(catalogueItemRepositoryProvider.future);
      // A failed read is "unknown", never "no items" (AV5), and is read
      // again on the next input.
      _items = (await repository.getAllForInterchange()).toNullable();
      _itemsStale = _items == null;
    }
    return AvailabilityLaneInputs(
      enabled: ref
          .read(settingsControllerProvider)
          .valueOrNull
          ?.autoPublishAvailability,
      activeCounts: counts,
      items: _items,
    );
  }
}
