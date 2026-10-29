/// Strict complete-snapshot preparation and R4 confirmation summaries (S8).
///
/// This phase performs local reads/builds only. Replacement always uses an
/// empty previous publication, so stale reuse records cannot satisfy required
/// cover/poster bytes or remove the other section from the reviewed content.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_publish_outcomes.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_digest.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_remote_anchor.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';

/// A complete snapshot and the safe confirmation projection derived from it.
final class CloudflareCompletePreparation {
  /// Creates the matched pair; the digest binds one to the other.
  const CloudflareCompletePreparation({
    required this.snapshot,
    required this.summary,
  });

  /// Full local artifacts/sections, retained only inside the operation.
  final PublishSnapshot snapshot;

  /// Small target/content/count projection safe for controller state.
  final PublishReplacementSummary summary;
}

/// Builds complete snapshots and their canonical confirmation identities.
final class CloudflareReplacementPreparation {
  /// Creates preparation over the ONE shared snapshot builder.
  const CloudflareReplacementPreparation({
    required PublishSnapshotBuilder snapshotBuilder,
    required int Function() clock,
    CloudflareArtifactStore? artifactStore,
  }) : _snapshotBuilder = snapshotBuilder,
       _clock = clock,
       _artifactStore = artifactStore;

  final PublishSnapshotBuilder _snapshotBuilder;
  final int Function() _clock;
  final CloudflareArtifactStore? _artifactStore;

  /// Uses one operation's spool for building and on-demand digest reads.
  CloudflareReplacementPreparation withArtifactStore(
    CloudflareArtifactStore store,
  ) => CloudflareReplacementPreparation(
    snapshotBuilder: _snapshotBuilder.withArtifactSink(
      CloudflareArtifactSink(store),
    ),
    clock: _clock,
    artifactStore: store,
  );

  /// Builds against [CloudflareSiteManifest.empty] in complete mode.
  ///
  /// [remoteAnchor] and [reason] are carried into the summary so the
  /// confirmation is bound to the remote state the user actually saw.
  Future<Either<Failure, CloudflareCompletePreparation>> prepare({
    required CloudflarePublishTarget target,
    required PublishRequestedSection requestedSection,
    required PublishInputs inputs,
    required CloudflareRemoteAnchor remoteAnchor,
    required PublishReplacementReason reason,
    String? previousSiteUrl,
    bool remoteChangedSinceReview = false,
  }) async {
    final built = await _snapshotBuilder.build(
      inputs: inputs,
      previous: CloudflareSiteManifest.empty,
      now: _clock(),
      mode: PublishMode.complete,
    );
    final failure = built.swap().toNullable();
    if (failure != null) return Left(failure);
    final snapshot = built.toNullable()!;
    final digest = await PublishSnapshotDigest.of(
      snapshot,
      readBytes: _readSpooledBytes,
    );
    final digestFailure = digest.swap().toNullable();
    if (digestFailure != null) return Left(digestFailure);

    return Right(
      CloudflareCompletePreparation(
        snapshot: snapshot,
        summary: PublishReplacementSummary(
          target: target,
          requestedSection: requestedSection,
          digest: digest.toNullable()!,
          catalogueItemCount: snapshot.catalogueItemCount,
          posterCount: snapshot.posterCount,
          availabilityOmitted: snapshot.availabilityOmitted,
          remoteAnchor: remoteAnchor,
          reason: reason,
          previousSiteUrl: previousSiteUrl,
          remoteChangedSinceReview: remoteChangedSinceReview,
        ),
      ),
    );
  }

  Future<List<int>?> _readSpooledBytes(String path) async {
    final asset = _artifactStore?.assetForPath(path);
    if (asset == null) return null;
    final output = BytesBuilder(copy: false);
    await for (final chunk in asset.bucketAsset.openValidated()) {
      output.add(chunk);
    }
    return output.takeBytes();
  }

  /// Reads ordinary or complete inputs, reusing an existing complete read.
  Future<PublishInputs?> readInputs({
    required PublishReads reads,
    required CloudflarePublishTarget target,
    required PublishRequestedSection section,
    required bool complete,
    PublishInputs? existing,
  }) async {
    if (existing != null && (existing.events != null || !complete)) {
      return existing;
    }
    final read = await _snapshotBuilder.read(
      reads: reads,
      target: target,
      includeEvents: complete || section == PublishRequestedSection.events,
    );
    return read.toNullable();
  }

  /// Produces a replacement-required result, including a fresh complete read
  /// when the initiating catalogue command had not read the events section.
  Future<PublishResult> prepareResult({
    required PublishReads reads,
    required CloudflarePublishTarget target,
    required PublishRequestedSection requestedSection,
    required PublishInputs inputs,
    required CloudflareRemoteAnchor remoteAnchor,
    required PublishReplacementReason reason,
    String? previousSiteUrl,
    bool remoteChangedSinceReview = false,
  }) async {
    final completeInputs = await readInputs(
      reads: reads,
      target: target,
      section: requestedSection,
      complete: true,
      existing: inputs,
    );
    if (completeInputs == null) {
      return const PublishFailure(PublishSnapshotBuilder.readFailedMessage);
    }
    final prepared = await prepare(
      target: target,
      requestedSection: requestedSection,
      inputs: completeInputs,
      remoteAnchor: remoteAnchor,
      reason: reason,
      previousSiteUrl: previousSiteUrl,
      remoteChangedSinceReview: remoteChangedSinceReview,
    );
    final failure = prepared.swap().toNullable();
    if (failure != null) return CloudflarePublishOutcomes.failure(failure);
    return PublishReplacementRequired(prepared.toNullable()!.summary);
  }
}
