/// Durable handoff between a committed catalogue import and preference save.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Target-bound public identity awaiting durable completion.
final class RestoreIdentityJournal {
  /// Creates a pending handoff.
  const RestoreIdentityJournal({
    required this.siteUrl,
    required this.addedDate,
    this.fingerprint,
  });

  /// Canonical active-target site this recovery is allowed to use.
  final String siteUrl;

  /// The one insert timestamp shared by every row in this restore.
  final int addedDate;

  /// Public identity read from that site; null means it had no descriptor.
  final String? fingerprint;
}

/// Non-secret preference storage for the one pending identity handoff.
abstract interface class RestoreIdentityJournalStore {
  /// Null means no pending handoff; corrupt storage is a typed failure.
  Future<Either<Failure, RestoreIdentityJournal?>> load();

  /// Replaces the pending handoff before catalogue writes begin.
  Future<Either<Failure, Unit>> save(RestoreIdentityJournal journal);

  /// Clears only after the settings write succeeds (or no import committed).
  Future<Either<Failure, Unit>> clear();
}
