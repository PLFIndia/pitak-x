/// What one availability-only publish sends (publish domain, pure Dart;
/// ADR 0019 Decisions 6, 9 and 10, plan C.4/C.5).
///
/// The lane (plan S6) decides it, and the active host's availability publish
/// carries it out: GitHub from plan S4, Cloudflare from plan S5.
///
/// Why not `AvailabilityRequest` (beginner note): that type tells a publish
/// that BUILDS a catalogue snapshot what to do with the file, and its "on"
/// case means "compute the set from this publish's own loan counts". An
/// availability-only publish reads no loans and builds no catalogue. It sends
/// a set the lane already computed and saved, which is what lets it run after
/// the vault has locked (AV7). Two different operations, so two types.
library;

import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';

/// The one change an availability-only publish makes.
///
/// Sealed (beginner note): the compiler makes every host handle both cases,
/// so a removal can never be mistaken for "publish an empty set". The two are
/// different public facts: an empty set says "everything is on the shelf",
/// a removal says "this site no longer publishes availability".
sealed class AvailabilityUpdate {
  const AvailabilityUpdate();
}

/// Publish [snapshot] as `availability.json` (the lane is on).
final class AvailabilityWrite extends AvailabilityUpdate {
  /// Creates the update.
  const AvailabilityWrite(this.snapshot);

  /// The saved "not available" set to publish.
  final AvailabilitySnapshot snapshot;

  @override
  String toString() => 'AvailabilityWrite($snapshot)';
}

/// Delete `availability.json` from the site (the lane was switched off,
/// plan AV4), so readers fall back to the inline tag in `books.json`.
final class AvailabilityDelete extends AvailabilityUpdate {
  /// Creates the update.
  const AvailabilityDelete();

  @override
  String toString() => 'AvailabilityDelete()';
}
