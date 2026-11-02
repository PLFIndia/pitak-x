/// `shared_preferences`-backed store for the availability lane
/// (infrastructure, AGENTS.md §3.3; ADR 0019 Decision 9, plan C.4).
///
/// ONE key holds the whole lane state as versioned JSON, so the pending set,
/// the published record, the GitHub commit times and the notice flag always
/// change together in one write.
///
/// Why SharedPreferences is acceptable here (beginner note): the state holds
/// only PUBLIC data — item keys that become public anyway, a content
/// fingerprint, timestamps and one flag. There is no borrower data, no count
/// and no token. AGENTS.md §6.3 keeps secrets out of SharedPreferences, and
/// there are none here (plan C.4, P8).
///
/// Decoding goes through `AvailabilityLaneState.decode` ONLY, which accepts a
/// stored value when every field is exactly as this build writes it. So:
///  - nothing stored → [AvailabilityLaneAbsent];
///  - anything damaged, oversized, of a newer version, or a storage error
///    while reading → [AvailabilityLaneUnreadable] — never "absent", and
///    never an empty "not available" list.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_state.dart';
import 'package:pitaka/features/publish/domain/availability/availability_lane_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the lane state in [SharedPreferences].
final class PrefsAvailabilityLaneStore implements AvailabilityLaneStore {
  /// Creates the store over [_prefs].
  const PrefsAvailabilityLaneStore(this._prefs);

  final SharedPreferences _prefs;

  /// Storage key. Public so tests can seed `setMockInitialValues`. The
  /// version lives inside the JSON (`AvailabilityLaneState.currentVersion`).
  static const String key = 'availability_lane_state';

  /// Upper bound on the stored text. A pending set holds at most
  /// `AvailabilitySnapshot.maxKeys` keys of 16 characters, about 1 MB as
  /// JSON; anything larger cannot be a value this build wrote.
  static const int maxRecordLength = 2 * 1024 * 1024;

  @override
  Future<AvailabilityLaneRead> read() async {
    try {
      // `get` instead of `getString`: a value of another type under this key
      // is damage to report, not a TypeError to crash on.
      final raw = _prefs.get(key);
      if (raw == null) return const AvailabilityLaneAbsent();
      if (raw is! String || raw.length > maxRecordLength) {
        return const AvailabilityLaneUnreadable();
      }
      return AvailabilityLaneState.decode(jsonDecode(raw));
    } on Exception {
      // Malformed JSON (FormatException) or a platform read error: damage or
      // "could not read", never "nothing stored".
      return const AvailabilityLaneUnreadable();
    }
  }

  @override
  Future<Either<Failure, Unit>> write(AvailabilityLaneState state) =>
      // The shared helper turns the plugin's success flag into a typed result
      // and repairs the cache after a failed write (fix-plan L9), so a failed
      // save can never look saved for the rest of the session.
      writePrefsString(
        _prefs,
        key,
        jsonEncode(state.toJson()),
        what: 'availability lane state write',
      );
}
