/// What a built backup actually carries (backup domain, docs/ARCHITECTURE.md §3 network).
///
/// The archive bytes plus the truth about the two OPTIONAL entries: the
/// library identity and the saved-libraries list are gathered best-effort —
/// a failure to read them must never block a catalogue backup, so the use
/// case proceeds without them and reports the omission here. The create page
/// turns a false flag into one plain sentence next to "Backup saved." — the
/// user must never believe an identity travels inside when it does not.
library;

import 'dart:typed_data';

/// The built archive plus its honest content flags.
final class CreateBackupResult {
  /// Creates the result.
  const CreateBackupResult({
    required this.bytes,
    required this.includesIdentity,
    required this.includesNetwork,
    this.missingPublishState = false,
  });

  /// The `.pitabak` archive bytes.
  final Uint8List bytes;

  /// Whether `identity.json` made it into the archive.
  final bool includesIdentity;

  /// Whether `network.json` (the saved-libraries list) made it in.
  final bool includesNetwork;

  /// True when this phone HAS a website publishing record but the backup
  /// does not carry it (it could not be read, or did not fit the entry's
  /// bounds). False both when it is inside and when there is none to carry
  /// (a library without a website) — only the first case needs a note.
  final bool missingPublishState;
}
