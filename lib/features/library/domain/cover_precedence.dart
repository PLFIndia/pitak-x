/// Cover precedence when an incoming row updates an existing one (M09).
///
/// User decision (2026-09-09): a cover the user produced on THIS device — a
/// photo of the physical book, stored as `covers/<uuid>.jpg` (or the legacy
/// `file://` form) — is the best cover that can exist for that book. It is
/// never replaced by a remote `https://` URL arriving through a JSON import or
/// a merge "take theirs". An incoming cover lands only when:
///  - the local row has no cover at all, or
///  - the local cover is itself just a remote URL (a newer URL may replace
///    an older one), or
///  - the incoming cover is a real local file (a bundle carrying the user's
///    own photos between devices — that is a photo too, and the newer intent).
///
/// Pure function (domain, AGENTS.md §3.1): both `ImportLibraryUseCase` and
/// `MergeLibraryUseCase` call it, so the rule cannot drift between paths.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';

/// Returns the cover reference the updated row should carry.
///
/// Neither argument is rewritten: the chosen value is returned exactly as
/// given. Blank/null [incoming] always keeps [existing].
String? resolveIncomingCover({
  required String? existing,
  required String? incoming,
}) {
  final incomingTrimmed = incoming?.trim() ?? '';
  if (incomingTrimmed.isEmpty) return existing;

  final existingTrimmed = existing?.trim() ?? '';
  if (existingTrimmed.isEmpty) return incoming;

  // Incoming local file (bundle): the user's own image wins over anything.
  if (CoverPaths.isLocal(incomingTrimmed)) return incoming;

  // Incoming is remote. A local photo beats it; a local remote URL does not.
  if (CoverPaths.isLocal(existingTrimmed)) return existing;
  return incoming;
}
