/// Runs ONE availability-only publish for the lane, inside the app-wide
/// publish queue (application layer; ADR 0019 Decision 7, plan C.4 "When the
/// timer fires").
///
/// What it does, in order, while the queue is held:
///  1. resolves the EXACT active target with fresh reads (gates a and c: an
///     active, connected host, and no pending move). The lane never re-uses a
///     target it resolved earlier;
///  2. for a removal, checks this phone's LOCAL record first: with no
///     recorded `availability.json` there is nothing of ours to delete
///     (R13), so nothing goes over the network;
///  3. runs the active host's availability use case (GitHub, plan S4, or
///     Cloudflare, plan S5). Gate b is checked inside it;
///  4. if a write came back "not ready" while the record still shows a file,
///     publishes the removal right away in the same queue turn. That file was
///     published against keys the live catalogue no longer carries, and keys
///     that match nothing would show every item as Available (plan S6,
///     handoff "safety point found in S4").
///
/// It returns as soon as the queue is released. Proving a GitHub commit live
/// (the deferred check) is the lane's job afterwards, never inside the queue.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/async/serial_op_queue.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_manifest_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart'
    show PublishManifestGateway;
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';

/// The GitHub availability publish (`PublishAvailabilityUseCase.call`).
typedef GitHubAvailabilityPublish =
    Future<AvailabilityPublishResult> Function({
      required GitHubPublishTarget target,
      required AvailabilityUpdate update,
    });

/// The Cloudflare availability publish
/// (`PublishAvailabilityToCloudflareUseCase.call`).
typedef CloudflareAvailabilityPublish =
    Future<AvailabilityPublishResult> Function({
      required CloudflarePublishTarget target,
      required AvailabilityUpdate update,
    });

/// How one lane run ended.
sealed class AvailabilityRun {
  const AvailabilityRun();
}

/// Nothing was sent: there is no active, connected host, or an ordinary
/// publish is not allowed right now (gates a and c). [reason] is the same
/// fixed sentence the catalogue publish shows.
final class AvailabilityRunBlocked extends AvailabilityRun {
  /// Creates the outcome.
  const AvailabilityRunBlocked(this.reason);

  /// Why, as a fixed sentence.
  final String reason;
}

/// The host's use case ran against [target].
final class AvailabilityRunFinished extends AvailabilityRun {
  /// Creates the outcome.
  const AvailabilityRunFinished({
    required this.target,
    required this.result,
    this.removal,
  });

  /// The exact site this run published to.
  final PublishTarget target;

  /// The use case's outcome for the requested update.
  final AvailabilityPublishResult result;

  /// The outcome of the stale-file removal that followed a "not ready"
  /// write in the same queue turn (step 4), or null when none was needed.
  final AvailabilityPublishResult? removal;
}

/// See the library comment.
final class AvailabilityPublishRunner {
  /// Creates the runner over the queue, the target resolver, both hosts'
  /// availability publishes and both local publish records.
  const AvailabilityPublishRunner({
    required SerialOpQueue queue,
    required Future<Either<Failure, PublishTarget>> Function() resolveTarget,
    required GitHubAvailabilityPublish gitHub,
    required CloudflareAvailabilityPublish cloudflare,
    required PublishManifestGateway gitHubRecord,
    required CloudflareManifestStore cloudflareRecord,
    Future<Either<Failure, Unit>> Function(PublishTarget target)? checkTarget,
  }) : _queue = queue,
       _resolveTarget = resolveTarget,
       _gitHub = gitHub,
       _cloudflare = cloudflare,
       _gitHubRecord = gitHubRecord,
       _cloudflareRecord = cloudflareRecord,
       _checkTarget = checkTarget;

  final SerialOpQueue _queue;
  final Future<Either<Failure, PublishTarget>> Function() _resolveTarget;
  final GitHubAvailabilityPublish _gitHub;
  final CloudflareAvailabilityPublish _cloudflare;
  final PublishManifestGateway _gitHubRecord;
  final CloudflareManifestStore _cloudflareRecord;
  final Future<Either<Failure, Unit>> Function(PublishTarget target)?
  _checkTarget;

  /// Shown when a use case throws instead of answering. A bug, not a site
  /// fact: nothing is claimed, and the lane retries later (AV11).
  static const String unexpectedMessage =
      'Availability could not be updated. Pitak will try again.';

  /// The active target as a HINT, read without the queue and without any
  /// network call: which host paces the lane, and whether the last published
  /// set went to this site. Every publish resolves the target again inside
  /// the queue. A left carries the fixed sentence that explains why there is
  /// no target.
  Future<Either<String, PublishTarget>> currentTarget() async =>
      (await _resolveTarget()).mapLeft(_reasonFor);

  /// Runs [update] inside the publish queue; see the library comment.
  Future<AvailabilityRun> call(AvailabilityUpdate update) =>
      _queue.enqueue(() async {
        final resolved = await _resolveTarget();
        final target = resolved.toNullable();
        if (target == null) {
          return AvailabilityRunBlocked(
            _reasonFor(resolved.swap().toNullable()!),
          );
        }
        final check = _checkTarget;
        if (check != null) {
          final allowed = await check(target);
          final failure = allowed.swap().toNullable();
          if (failure != null) {
            return AvailabilityRunBlocked(_reasonFor(failure));
          }
        }
        if (update is AvailabilityDelete && !_recordShowsFile(target)) {
          return AvailabilityRunFinished(
            target: target,
            result: const AvailabilityAlreadyPublished(),
          );
        }
        final result = await _publish(target, update);
        if (update is AvailabilityWrite &&
            result is AvailabilityNotReady &&
            result.staleFileRecorded) {
          return AvailabilityRunFinished(
            target: target,
            result: result,
            removal: await _publish(target, const AvailabilityDelete()),
          );
        }
        return AvailabilityRunFinished(target: target, result: result);
      });

  Future<AvailabilityPublishResult> _publish(
    PublishTarget target,
    AvailabilityUpdate update,
  ) async {
    try {
      return await switch (target) {
        final GitHubPublishTarget gitHub => _gitHub(
          target: gitHub,
          update: update,
        ),
        final CloudflarePublishTarget cloudflare => _cloudflare(
          target: cloudflare,
          update: update,
        ),
      };
    } on Exception catch (error) {
      // Type only (AGENTS §6.2): exception text may carry URLs or response
      // detail. Pending keeps the set and retries on the backoff (AV11).
      appLog('availability publish threw: ${error.runtimeType}');
      return const AvailabilityPending(unexpectedMessage);
    }
  }

  /// True when this phone's local record of [target] (or its unconfirmed
  /// Cloudflare attempt) shows `availability.json`. A local read only.
  bool _recordShowsFile(PublishTarget target) {
    const path = AvailabilityDocument.path;
    switch (target) {
      case final GitHubPublishTarget gitHub:
        final record = _gitHubRecord.load();
        return record.repo == gitHub.ownerRepo && record.shaFor(path) != null;
      case final CloudflarePublishTarget cloudflare:
        // The unconfirmed attempt counts too: the shared start may promote it
        // to the record (L4) before the use case decides.
        final record = _cloudflareRecord.load().forTarget(cloudflare);
        final attempt = _cloudflareRecord.loadPending().forTarget(cloudflare);
        return record.shaFor(path) != null || attempt.shaFor(path) != null;
    }
  }

  static String _reasonFor(Failure failure) =>
      CloudflarePublishOutcomes.failure(failure).reason;
}
