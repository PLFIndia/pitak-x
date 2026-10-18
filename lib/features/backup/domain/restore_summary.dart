/// Outcome of a successful backup restore (AGENTS.md §3.1, pure Dart).
library;

import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/vault/domain/loan_integrity.dart';

/// Counts + integrity findings from an applied restore.
class RestoreSummary {
  /// Creates a restore summary.
  const RestoreSummary({
    required this.booksRestored,
    required this.wishlistRestored,
    required this.borrowersRestored,
    required this.loansRestored,
    this.danglingLoans = const [],
    this.existingVaultKept = false,
    this.coversDropped = 0,
    this.restoredIdentity,
    this.restoredNetwork,
    this.identityInvalid = false,
    this.networkInvalid = false,
    this.identityAdopted = false,
    this.networkApplied = false,
    this.networkRestored = 0,
    this.networkRowsDropped = 0,
  });

  /// Number of library books written.
  final int booksRestored;

  /// Number of wishlist entries written.
  final int wishlistRestored;

  /// Number of vault borrowers read.
  final int borrowersRestored;

  /// Number of vault loans read.
  final int loansRestored;

  /// Loans whose `bookId`/`borrowerId` did not resolve after restore. Empty
  /// means full cross-DB referential integrity (the expected case).
  final List<DanglingLoan> danglingLoans;

  /// True when the archive had no vault and the device's vault was retained.
  /// M03: successful retention now requires a fresh unlocked integrity check
  /// and preservation of every loan's book identity, including returned loans.
  final bool existingVaultKept;

  /// Cover references normalised to null by validation (M15): the restored
  /// row pointed at a site the app no longer loads covers from, so the link
  /// was removed rather than persisted. The book itself is kept.
  final int coversDropped;

  /// The validated library identity parsed from the archive's
  /// `identity.json` (libNetwork.md §3.4) — null when the archive carried no
  /// usable identity (absent, or invalid: see [identityInvalid]). Parsed and
  /// validated by the restorer; APPLIED by the restore controller after the
  /// catalogue switch (see [identityAdopted]).
  final ({String id, String name})? restoredIdentity;

  /// The validated saved-libraries rows parsed from the archive's
  /// `network.json` — null when the archive carried no usable list (absent,
  /// or unreadable: see [networkInvalid]). An empty LIST is meaningful: the
  /// backup legitimately had no saved libraries. Applied by the restore
  /// controller via `NetworkRepository.replaceAll` (see [networkApplied] and
  /// [networkRestored]). Invalid, duplicate, and over-cap entries never reach
  /// this list — they are counted in [networkRowsDropped] (§6).
  final List<NetworkLibrary>? restoredNetwork;

  /// True when the archive declared an identity (`hasIdentity`) but the
  /// entry failed validation — the user should hear "could not be read",
  /// not nothing.
  final bool identityInvalid;

  /// True when the archive declared a network list (`hasNetwork`) but the
  /// entry could not be parsed.
  final bool networkInvalid;

  /// True when [restoredIdentity] was actually adopted through the namespace
  /// port. Set AFTER the catalogue switch by the restore controller (a Left
  /// leaves it false — the catalogue restore is never rolled back for this;
  /// §5.10).
  final bool identityAdopted;

  /// True when the `replaceAll` of [restoredNetwork] actually succeeded.
  /// Set together with [identityAdopted] by the restore controller. This is
  /// what the UI branches on — inferring it from [networkRestored] alone
  /// cannot tell "applied an honestly empty list" from "the write failed"
  /// (review M9).
  final bool networkApplied;

  /// How many [restoredNetwork] rows were actually written (0 when the
  /// replaceAll failed).
  final int networkRestored;

  /// How many entries the archive's `network.json` DROPPED at decode time —
  /// invalid rows, first-wins duplicates (siteUrl / fingerprint / id), and
  /// rows beyond the codec's cap (§6: "dropped and counted"; review M9). The
  /// page says so in one sentence; these rows never reach [restoredNetwork].
  final int networkRowsDropped;

  /// Returns a copy with the post-restore adoption outcomes filled in (the
  /// restorer parses but never applies identity/network — that is the
  /// controller's job, after the catalogue switch).
  RestoreSummary withAdoptionResults({
    required bool identityAdopted,
    required bool networkApplied,
    required int networkRestored,
  }) {
    return RestoreSummary(
      booksRestored: booksRestored,
      wishlistRestored: wishlistRestored,
      borrowersRestored: borrowersRestored,
      loansRestored: loansRestored,
      danglingLoans: danglingLoans,
      existingVaultKept: existingVaultKept,
      coversDropped: coversDropped,
      restoredIdentity: restoredIdentity,
      restoredNetwork: restoredNetwork,
      identityInvalid: identityInvalid,
      networkInvalid: networkInvalid,
      identityAdopted: identityAdopted,
      networkApplied: networkApplied,
      networkRestored: networkRestored,
      networkRowsDropped: networkRowsDropped,
    );
  }

  /// True when restore changed anything the user should know about beyond
  /// the row counts (today: dropped cover links).
  bool get hasAdjustments => coversDropped > 0;

  /// True when restored loans resolve, or retained loan links were verified
  /// and preserved. A retained but unchecked vault can no longer succeed.
  bool get isIntact => danglingLoans.isEmpty;
}
