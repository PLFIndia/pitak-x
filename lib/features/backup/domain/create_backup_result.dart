/// What a built backup actually carries (backup domain, docs/ARCHITECTURE.md §3 network).
///
/// The archive file plus the truth about the two OPTIONAL entries: the
/// library identity and the saved-libraries list are gathered best-effort —
/// a failure to read them must never block a catalogue backup, so the use
/// case proceeds without them and reports the omission here. The create page
/// turns a false flag into one plain sentence next to "Backup saved." — the
/// user must never believe an identity travels inside when it does not.
///
/// The same honesty rule covers cover pictures (BR3, decision D10): a picture
/// too large for a backup is left out, and the items it belongs to are named
/// here so the page can say so.
///
/// And it covers the borrowers vault (BR4 rider 2, decision D17): a vault
/// whose last change did not finish is left out, and `vaultLeftOut` says so.
///
/// Since BR4 the archive is a FILE in a private folder of the app, not
/// bytes in memory. Whoever receives this result must hand it back to
/// `CreateBackupUseCase.discard` when done, so the file does not stay
/// behind: it is a plain copy of the whole library.
library;

/// The built archive plus its honest content flags.
final class CreateBackupResult {
  /// Creates the result.
  const CreateBackupResult({
    required this.path,
    required this.sizeBytes,
    required this.includesIdentity,
    required this.includesNetwork,
    this.missingPublishState = false,
    this.coversLeftOut = const [],
    this.vaultLeftOut = false,
  });

  /// Absolute path of the finished `.pitabak` file. Its file name is the
  /// name the user sees in the share sheet.
  final String path;

  /// Size of that file in bytes.
  final int sizeBytes;

  /// Whether `identity.json` made it into the archive.
  final bool includesIdentity;

  /// Whether `network.json` (the saved-libraries list) made it in.
  final bool includesNetwork;

  /// True when this phone HAS a website publishing record but the backup
  /// does not carry it (it could not be read, or did not fit the entry's
  /// bounds). False both when it is inside and when there is none to carry
  /// (a library without a website) — only the first case needs a note.
  final bool missingPublishState;

  /// Titles of the items whose cover picture is NOT inside because the
  /// picture file is too large for a backup. The items themselves are
  /// inside. Empty in the normal case.
  final List<String> coversLeftOut;

  /// True when this phone HAS a borrowers vault and it is NOT inside the
  /// archive, because its last change did not finish. The page must say so:
  /// without the note the user would believe borrowers and loans are safe
  /// in this file. False both when the vault is inside and when there is
  /// none.
  final bool vaultLeftOut;
}
