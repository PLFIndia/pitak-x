/// Marks the published item keys as "no longer vouched for" before an
/// operation that changes what item ids name (application layer; ADR 0019
/// Decision 3, plan J9 decided in S6).
///
/// The risk it closes (beginner note): `catalogueKeyed` in both publish
/// records says "the live `books.json` carries keys THIS phone can match".
/// The records and the cover salt live outside the data that a restore
/// replaces, so restoring another library's backup kept the flag while the
/// restored ids named other books. The lane would then have published the
/// restored library's loans against the live catalogue's keys: wrong tags on
/// real books, and gate 7b could not see it. An overwrite merge gives every
/// book a new id, with the same effect.
///
/// What it does, inside the app-wide publish queue so no publish can run in
/// between:
///  1. clears `catalogueKeyed` in the GitHub record, the Cloudflare record
///     and the unconfirmed Cloudflare attempt (which may be promoted later);
///  2. clears the lane's saved sets (their keys came from the old ids);
///  3. only then runs the change (the restore's generation switch, or the
///     overwrite), and tells a running lane to forget the sets it holds in
///     memory.
///
/// If step 1 or 2 cannot be saved, the change does NOT run and
/// [CatalogueKeysResetRefused] is thrown: the device stays exactly as it was
/// (fail closed). Afterwards the lane says "Publish your catalogue once…",
/// any publish that cannot write a fresh set deletes the old
/// `availability.json`, and the next catalogue publish writes fresh keys.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_repository.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;

/// Thrown when the keys could not be marked unusable, so the change that
/// would have made them wrong was not run.
final class CatalogueKeysResetRefused implements Exception {
  /// Creates the refusal.
  const CatalogueKeysResetRefused();

  /// A fixed, safe sentence: restore reports a thrown activation through its
  /// typed failure, which may show this text.
  @override
  String toString() =>
      'Pitak could not update its publishing record. Nothing was changed.';
}

/// See the library comment.
final class CatalogueKeysReset {
  /// Creates the reset over the publish queue, both publish records and the
  /// lane's store.
  const CatalogueKeysReset({
    required SerialOpQueue queue,
    required PublishManifestGateway gitHubRecord,
    required CloudflareManifestStore cloudflareRecord,
    required AvailabilityLaneRepository lane,
    void Function()? onIdsChanged,
  }) : _queue = queue,
       _gitHubRecord = gitHubRecord,
       _cloudflareRecord = cloudflareRecord,
       _lane = lane,
       _onIdsChanged = onIdsChanged;

  final SerialOpQueue _queue;
  final PublishManifestGateway _gitHubRecord;
  final CloudflareManifestStore _cloudflareRecord;
  final AvailabilityLaneRepository _lane;

  /// Told after a change ran, still inside the queue, so a running lane
  /// forgets the sets it holds in memory (they were computed from the old
  /// ids) before any later publish can start.
  final void Function()? _onIdsChanged;

  /// The `CatalogueIdsChangeGuard` implementation: resets, then runs
  /// [change], both inside the publish queue.
  ///
  /// Must not be called from inside the publish queue (a nested enqueue
  /// would wait for itself). Restore and merge are not publish commands, so
  /// they never hold it.
  Future<T> beforeIdsChange<T>(Future<T> Function() change) =>
      _queue.enqueue(() async {
        final reset = await _reset();
        if (reset.isLeft()) throw const CatalogueKeysResetRefused();
        final result = await change();
        _onIdsChanged?.call();
        return result;
      });

  Future<Either<Failure, Unit>> _reset() async {
    final gitHub = _gitHubRecord.load();
    if (gitHub.catalogueKeyed) {
      final saved = _gitHubRecord.save(gitHub.withoutCatalogueKeys());
      if (saved.isLeft()) return saved;
    }
    final cloudflare = _cloudflareRecord.load();
    if (cloudflare.catalogueKeyed) {
      final saved = _cloudflareRecord.save(cloudflare.withoutCatalogueKeys());
      if (saved.isLeft()) return saved;
    }
    final attempt = _cloudflareRecord.loadPending();
    if (attempt.catalogueKeyed) {
      final saved = _cloudflareRecord.savePending(
        attempt.withoutCatalogueKeys(),
      );
      if (saved.isLeft()) return saved;
    }
    final lane = await _lane.update((state) => state.withoutSnapshots());
    return lane.map((_) => unit);
  }
}
