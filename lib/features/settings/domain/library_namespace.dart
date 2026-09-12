/// The library's cross-device identity (settings domain, pure Dart).
///
/// Two devices share a "namespace" when they hold the same library ID: a
/// merge between them applies automatically, while a file from a DIFFERENT ID
/// stops for a Join / Overwrite decision (PLAN-merge.md D40). The ID and the
/// display name are settings, so the single serialised settings writer
/// (`SettingsController`, M16) is the only thing allowed to change them.
///
/// N07 (astra-review.md): the merge use case used to write these two keys
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
  const LibraryIdentity({required this.id, required this.name});

  /// The 32-char library ID (minted on first read, never blank on success).
  final String id;

  /// The library display name; blank when the user never set one.
  final String name;
}

/// Reads and adopts the library identity through its single owner.
abstract interface class LibraryNamespace {
  /// Returns the current identity, minting an ID on first use. A failed mint
  /// or read is a left — callers must not proceed with a phantom ID (M17).
  Future<Either<Failure, LibraryIdentity>> current();

  /// Adopts [id] (already validated by `LibraryId.normalizeOrNull`) and, when
  /// [name] is not blank, the display name too — as ONE atomic step from the
  /// caller's point of view: both persist and the in-memory settings update
  /// together, or a left is returned and nothing is published.
  Future<Either<Failure, Unit>> adopt({
    required String id,
    required String name,
  });
}
