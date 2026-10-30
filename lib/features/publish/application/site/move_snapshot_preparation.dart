/// Shared strict complete-snapshot preparation for moves in either direction.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_digest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// One operation's built snapshot and its small, safe confirmation projection.
final class MovePreparedSnapshot {
  /// Creates the matched pair.
  const MovePreparedSnapshot({
    required this.snapshot,
    required this.confirmation,
  });

  /// Complete artifacts, retained only inside the destination operation.
  final PublishSnapshot snapshot;

  /// Digest and counts shown to the user; no artifact bytes or credentials.
  final MoveSiteConfirmation confirmation;
}

/// Builds through the ONE snapshot builder used by ordinary publishing.
final class MoveSnapshotPreparation {
  /// Creates preparation over an empty previous-publication record.
  const MoveSnapshotPreparation({
    required PublishSnapshotBuilder builder,
    required PreviousPublication emptyPrevious,
    required int Function() clock,
    PublishArtifactBytesReader? readBytes,
  }) : _builder = builder,
       _emptyPrevious = emptyPrevious,
       _clock = clock,
       _readBytes = readBytes;

  final PublishSnapshotBuilder _builder;
  final PreviousPublication _emptyPrevious;
  final int Function() _clock;
  final PublishArtifactBytesReader? _readBytes;

  /// Re-reads and rebuilds, so confirmation can never deploy stale content.
  Future<Either<Failure, MovePreparedSnapshot>> call({
    required PublishReads reads,
    required PublishTarget oldTarget,
    required PublishTarget newTarget,
    required MoveSourceAnchor sourceAnchor,
  }) async {
    final inputs = await _builder.read(
      reads: reads,
      target: newTarget,
      // A move carries a COMPLETE site: both sections are required.
      sections: const {SiteSection.catalogue, SiteSection.events},
    );
    if (inputs case Left(value: final failure)) return Left(failure);
    final built = await _builder.build(
      inputs: inputs.toNullable()!,
      previous: _emptyPrevious,
      now: _clock(),
      mode: PublishMode.complete,
    );
    if (built case Left(value: final failure)) return Left(failure);
    final snapshot = built.toNullable()!;
    if (snapshot.events == null) {
      return const Left(
        ValidationFailure('The events snapshot is unavailable.'),
      );
    }
    final digest = await PublishSnapshotDigest.of(
      snapshot,
      readBytes: _readBytes,
    );
    if (digest case Left(value: final failure)) return Left(failure);
    return Right(
      MovePreparedSnapshot(
        snapshot: snapshot,
        confirmation: MoveSiteConfirmation(
          oldTarget: oldTarget,
          newTarget: newTarget,
          sourceAnchor: sourceAnchor,
          digest: digest.toNullable()!,
          catalogueItemCount: snapshot.catalogueItemCount,
          posterCount: snapshot.posterCount,
          availabilityOmitted: snapshot.availabilityOmitted,
        ),
      ),
    );
  }
}
