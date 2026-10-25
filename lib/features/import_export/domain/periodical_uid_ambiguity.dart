/// Detects a file-level magazine-title identity collision (import/export
/// domain, pure Dart; magazine remediation S1 canonicalisation + S4).
///
/// WHY THIS EXISTS (beginner note): S1 canonicalises a periodical UID by
/// trimming surrounding whitespace. That makes `" series-1 "` and `"series-1"`
/// the SAME identity — which is exactly what matching wants. It also creates
/// one trap: a file that spells the same UID two different ways is claiming
/// two different titles are one series. Skipping the second row would silently
/// merge them, so the WHOLE file must be refused instead (fail closed, AGENTS
/// §2.7).
///
/// The JSON parser can see the raw spellings; the import/merge gate re-checks
/// payloads that were built by hand. Both use this single rule, so they can
/// never drift apart.
library;

import 'package:pitaka/features/library/domain/periodical_identity.dart';

/// The user-facing refusal for a trim-created periodical UID collision.
///
/// One constant because the parser, the import gate, and every future reader
/// must show the user the SAME sentence for the same file.
const String kPeriodicalUidTrimCollisionMessage =
    'Two magazine titles have different UIDs that become identical '
    'after trimming. Import was cancelled to avoid merging them.';

/// Accumulates the RAW UID spellings of one file and reports the collision.
///
/// Exact repeats are NOT a collision: the import rule is first-row-wins, so a
/// later row with the same spelling is reported as a skip, never as a fatal
/// file error.
final class PeriodicalUidAmbiguityScan {
  final _rawByCanonical = <String, String>{};

  /// Records [rawUid] and returns true when it is a SECOND, different spelling
  /// of an identity this scan has already seen.
  ///
  /// A null or blank UID is ignored: a series without an identity cannot
  /// collide with anything.
  bool isAmbiguous(String? rawUid) {
    if (rawUid == null) return false;
    final canonical = canonicalPeriodicalUid(rawUid);
    if (canonical.isEmpty) return false;
    final previous = _rawByCanonical[canonical];
    if (previous == null) {
      _rawByCanonical[canonical] = rawUid;
      return false;
    }
    return previous != rawUid;
  }
}
