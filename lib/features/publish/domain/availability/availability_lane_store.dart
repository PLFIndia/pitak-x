/// Storage port for the availability lane (publish domain, pure Dart;
/// ADR 0019 Decision 9, plan C.4).
///
/// A port (beginner note) is an interface the domain declares and the
/// infrastructure layer implements — here `PrefsAvailabilityLaneStore`
/// (plan S6), one versioned SharedPreferences JSON key. Tests use an
/// in-memory fake, so the lane never touches real storage in a test.
///
/// The contract every implementation must keep:
///  - `read` tells "nothing stored" ([AvailabilityLaneAbsent]) apart from
///    "stored but damaged" ([AvailabilityLaneUnreadable]), and decodes ONLY
///    through `AvailabilityLaneState.decode`, so a damaged value can never
///    become an empty "not available" list;
///  - a storage error while reading is [AvailabilityLaneUnreadable], never
///    [AvailabilityLaneAbsent]: "I could not read it" is not "there is
///    nothing";
///  - `write` reports failure as a value, never by throwing.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';

/// Reads and writes the lane's saved state.
abstract interface class AvailabilityLaneStore {
  /// Reads the saved state; see the library comment for the three outcomes.
  Future<AvailabilityLaneRead> read();

  /// Replaces the saved state with [state].
  Future<Either<Failure, Unit>> write(AvailabilityLaneState state);
}
