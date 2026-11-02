/// The two ports the backup feature uses to carry the publishing record
/// (publish domain; plan CV6/CV7, ADR 0014 amendment of 2026-11-02).
///
/// Declared here so the backup feature depends on contracts, not on the
/// publish feature's stores: `CreateBackupUseCase` reads through
/// [PublishStateBackupSource], `RestoreController` adopts through
/// [PublishStateAdopter]. Both are implemented in the publish application
/// layer and wired in `core/di`.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';

/// Reads this phone's publishing record for a backup.
// ignore: one_member_abstracts
abstract interface class PublishStateBackupSource {
  /// The record to carry, `Right(null)` when this phone has published
  /// nothing worth carrying, or a `Left` when it could not be read (the
  /// backup then goes ahead without it and says so). Never throws.
  Future<Either<Failure, PublishStateBackup?>> forBackup();
}

/// Applies a restored backup's publishing record to this phone.
// ignore: one_member_abstracts
abstract interface class PublishStateAdopter {
  /// Adopts [archived] when `PublishStateAdoptionRule` allows it, after the
  /// restored data is active. Additive over the restore: it never throws and
  /// never undoes the restore; a failure leaves this phone's own state.
  Future<PublishStateRestoreOutcome> adoptRestored(PublishStateBackup archived);
}
