/// Builds the summary of a finished restore (infrastructure): phase 8 of
/// the pipeline in `restore_backup.dart`.
///
/// WHY THIS FILE EXISTS (beginner note): when a restore has switched to the
/// new data generation, the last step only LOOKS at what the earlier phases
/// produced and writes it down for the user: how many rows came back,
/// which loans no longer find their book or borrower, which additive
/// entries could not be read, which cover pictures were left out. It
/// changes nothing on the device, so it is a pure function of its inputs
/// and lives here, as the other closed phases of a restore do
/// (`restore_backup.dart` sits close to the 500-line ceiling).
library;

import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/cover_item_titles.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart';
import 'package:pitaka/features/backup/infrastructure/restore_item_details.dart';
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/loan_integrity.dart';

/// The summary of a restore that has just gone live.
///
/// [legacy] holds the rows that were written, [applied] the counts of the
/// kinds/details join (W2), [extras] the additive entries as far as they
/// could be read, [vaultData] what the restored vault holds (empty when
/// the backup carried none). [existingVaultKept] says the device's own
/// vault was retained. [coversLeftOut] are the file names of the cover
/// pictures that were above their cap and were not restored.
RestoreSummary summariseRestore({
  required BackupManifest manifest,
  required BackupExtras extras,
  required LegacyCatalogueRows legacy,
  required RestoredItemDetails applied,
  required VaultData vaultData,
  required bool existingVaultKept,
  required List<String> coversLeftOut,
}) {
  final identity = extras.identity;
  final network = extras.network;

  // Cross-DB loan integrity over the FFI vault result.
  final dangling = LoanIntegrity.findDangling(
    loans: vaultData.loans,
    knownBookIds: legacy.books.map((b) => b.id).toSet(),
    knownBorrowerIds: vaultData.borrowers.map((b) => b.id).toSet(),
  );

  return RestoreSummary(
    booksRestored: legacy.books.length,
    wishlistRestored: legacy.wishlist.length,
    borrowersRestored: vaultData.borrowers.length,
    loansRestored: vaultData.loans.length,
    danglingLoans: dangling,
    existingVaultKept: existingVaultKept,
    // M15: cover refs dropped by validation (unsupported hosts).
    coversDropped: legacy.coversDropped,
    // D18 + D23: the items whose cover picture was above its cap and was
    // not restored, by title: books, wishlist entries, magazine titles. A
    // left-out picture no restored item refers to names nobody. Empty when
    // the backup's covers are not used at all.
    coverPicturesLeftOut: titlesOfItemsWithCover(
      coverLeaves: coversLeftOut.toSet(),
      books: legacy.books,
      wishlist: legacy.wishlist,
      periodicals: legacy.periodicals,
    ),
    // §3.4: parsed + validated, NOT yet applied — the controller adopts
    // the identity and replaces the network rows after the catalogue
    // switch has succeeded.
    restoredIdentity: identity == null
        ? null
        : (id: identity.id, name: identity.name),
    restoredPublishedFingerprint: identity?.publishedFingerprint,
    restoredNetwork: network?.rows,
    networkRowsDropped: network?.dropped ?? 0,
    identityInvalid: manifest.hasIdentity && identity == null,
    networkInvalid: manifest.hasNetwork && network == null,
    // W2: the kinds/details join counts. An entry that was DECLARED but
    // unreadable is flagged (everything else restores regardless — the
    // affected rows came back as books, which the counts show).
    kindsApplied: applied.kindsApplied,
    periodicalsRestored: legacy.periodicals.length,
    issuesLinked: applied.issuesLinked,
    issuesDetached: applied.issuesDetached,
    issueEntriesDropped: applied.issueEntriesDropped,
    rowsSkippedUnknownKind: applied.rowsSkippedUnknownKind,
    periodicalsDropped: applied.periodicalsDropped,
    itemKindsInvalid: manifest.hasItemKinds && extras.itemKinds == null,
    periodicalsInvalid: manifest.hasPeriodicals && extras.periodicals == null,
    // Plan CV6/CV7: parsed here, adopted (or not) by the controller after
    // the switch, inside the publish queue.
    restoredPublishState: extras.publishState,
    publishStateInvalid:
        manifest.hasPublishState && extras.publishState == null,
  );
}
