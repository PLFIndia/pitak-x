/// The library's cross-device identity (settings domain, pure Dart).
///
/// Two devices share a "namespace" when they hold the same library ID: a
/// merge between them applies automatically, while a file from a DIFFERENT ID
/// stops for a Join / Overwrite decision (PLAN-merge.md D40). The ID and the
/// display name are settings, so the single serialised settings writer
/// (`SettingsController`, M16) is the only thing allowed to change them.
///
/// Review finding N07: the merge use case used to write these two keys
/// straight into the settings repository, BEHIND the controller. Disk was
/// right, but the in-memory settings every screen watches (drawer header,
/// library title, export envelope, publish site name) kept the OLD name until
/// the app restarted. This port is how the use case asks the controller to do
/// it instead — the same shape as `CatalogueReplacementGuard`, which the vault
/// session controller implements for the same "one owner" reason.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// This device's current library identity.
class LibraryIdentity {
  /// Creates an identity snapshot.
  const LibraryIdentity({
    required this.id,
    required this.name,
    this.publishedFingerprint,
  });

  /// The 32-char library ID (minted on first read, never blank on success).
  final String id;

  /// The library display name; blank when the user never set one.
  final String name;

  /// Recovered public fingerprint, when it differs from the derived label.
  final String? publishedFingerprint;
}

/// What [LibraryNamespace.adopt] actually changed on this device.
enum LibraryAdoptionOutcome {
  /// Nothing changed: the previous identity is in force on disk AND in
  /// memory. Either a write was refused and `adopt` rolled back what had
  /// landed, or the very first write was refused.
  notAdopted,

  /// The incoming ID (and its name, when the file carried one) is this
  /// device's identity, on disk and in memory.
  adopted,

  /// The incoming ID was saved but its name was not, and the ID could not be
  /// rolled back either. Disk and memory BOTH hold the new ID with the
  /// previous name, so nothing may claim the old identity is still in force.
  partiallyAdopted,
}

/// The result of one adoption: what happened, and the failure behind a
/// non-adopted outcome (null for [LibraryAdoptionOutcome.adopted]).
///
/// Why a record (beginner note): the caller needs two small facts, not a
/// new type with behaviour. A record keeps the port honest without adding a
/// framework or a generated class for two fields.
typedef LibraryAdoption = ({LibraryAdoptionOutcome outcome, Failure? failure});

/// Reads and adopts the library identity through its single owner.
abstract interface class LibraryNamespace {
  /// Returns the current identity, minting an ID on first use. A failed mint
  /// or read is a left — callers must not proceed with a phantom ID (M17).
  Future<Either<Failure, LibraryIdentity>> current();

  /// Adopts [id] (already validated by `LibraryId.normalizeOrNull`) and, when
  /// [name] is not blank, the display name too, in ONE queued turn.
  ///
  /// The two preferences cannot be written in one transaction (the settings
  /// store has no multi-key commit), so this is NOT promised to leave disk
  /// untouched on every failure. What it does promise:
  ///  - a refused ID write changes nothing ([LibraryAdoptionOutcome
  ///    .notAdopted]);
  ///  - a refused name write rolls the ID back; if that rollback succeeds the
  ///    outcome is [LibraryAdoptionOutcome.notAdopted] and memory still holds
  ///    the old identity;
  ///  - if the rollback itself fails the outcome is [LibraryAdoptionOutcome
  ///    .partiallyAdopted] and memory is published as the TRUTH (new ID,
  ///    previous name) — never the old ID while disk holds the new one.
  Future<LibraryAdoption> adopt({
    required String id,
    required String name,
    String? publishedFingerprint,
  });
}
