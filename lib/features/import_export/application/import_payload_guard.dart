/// File-level refusals shared by every use case that APPLIES a parsed payload
/// (application layer; magazine remediation S1 + S4, findings H1/H2/H3/M3).
///
/// WHY A GUARD (beginner note): a normal import is fail-soft — one bad row is
/// skipped and reported while the rest is applied. A file whose magazine-title
/// identities collide after trimming is different: applying "the rest" would
/// merge two different titles into one series. Both the import and the merge
/// use case must therefore refuse such a file BEFORE any read of the library
/// or any repository write. This guard answers that one question for both, so
/// the rule exists exactly once.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/import_export/domain/periodical_uid_ambiguity.dart';

/// Stateless gate over an [ImportPayload].
abstract final class ImportPayloadGuard {
  /// The refusal that forbids ANY write for [payload], or null when the file
  /// may be applied.
  ///
  /// Two checks, in order:
  ///  1. the parser's own fatal list — it still holds the raw JSON evidence;
  ///  2. a re-scan of the payload's raw UID spellings, which protects callers
  ///     that build an [ImportPayload] directly instead of parsing text (the
  ///     parser normalises rows, so the collision is invisible in them).
  static ValidationFailure? refusal(ImportPayload payload) {
    if (payload.fatalErrors.isNotEmpty) {
      return ValidationFailure(payload.fatalErrors.join(' '));
    }
    final scan = PeriodicalUidAmbiguityScan();
    for (final periodical in payload.periodicals) {
      if (scan.isAmbiguous(periodical.periodicalUid)) {
        return const ValidationFailure(kPeriodicalUidTrimCollisionMessage);
      }
    }
    return null;
  }
}
