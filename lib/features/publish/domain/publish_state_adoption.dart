/// When a restored phone may take over the backup's publishing record
/// (publish domain, pure Dart; plan CV7 as decided by the product owner on
/// 2026-11-02, ADR 0014 amendment, ADR 0020 Decision 7).
///
/// The rule in one sentence (beginner note): adopt only on a phone that has
/// not published anything itself, and whose own connection — if it has one
/// — points at the very site the backup describes.
///
/// Why "has not published" and not merely "same site": a phone that already
/// published holds a record that is NEWER than the backup's. Taking the older
/// record would make Pitak forget files it published since — they would stay
/// on the site for good — and, with another salt, rename every cover back.
/// The most common restore (the same phone restoring its own backup) would
/// hit exactly that. So such a phone keeps its own state and says so (the
/// product owner's choice at the start of S11).
///
/// Everything this phone has "in flight" also blocks adoption: a pending
/// move, an unconfirmed Cloudflare deploy. They belong to this phone.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host_state.dart';

/// What a restore did with the backup's publishing record.
enum PublishStateRestoreOutcome {
  /// This phone now uses the backup's cover salt, records and site: covers
  /// already online are not uploaded again.
  adopted,

  /// This phone already publishes (or is connected to another site, or has
  /// work in flight), so its own publishing state was kept unchanged.
  keptThisPhone,

  /// The record could not be applied — this phone's state could not be read,
  /// or a write failed and was undone. Nothing changed (fail closed).
  notApplied,
}

/// What this phone already has, read inside the publish queue.
final class PhonePublishSetup {
  /// Creates the snapshot.
  const PhonePublishSetup({
    required this.journal,
    required this.gitHubRecord,
    required this.cloudflareRecord,
    required this.cloudflareAttempt,
    required this.gitHubConnection,
    required this.cloudflareConnection,
  });

  /// The host journal, or null when this phone never wrote one.
  final PublishHostState? journal;

  /// This phone's GitHub record.
  final PublishManifest gitHubRecord;

  /// This phone's Cloudflare record.
  final CloudflareSiteManifest cloudflareRecord;

  /// This phone's unconfirmed Cloudflare deploy (empty when none).
  final CloudflareSiteManifest cloudflareAttempt;

  /// The repository this phone's GitHub sign-in publishes to, if any.
  final GitHubPublishTarget? gitHubConnection;

  /// The Worker this phone's Cloudflare connection publishes to, if any.
  final CloudflarePublishTarget? cloudflareConnection;
}

/// The adoption rule (see the library comment).
abstract final class PublishStateAdoptionRule {
  /// True when [phone] may adopt [archived].
  static bool mayAdopt({
    required PhonePublishSetup phone,
    required PublishStateBackup archived,
  }) {
    final journal = phone.journal;
    // 1. Anything this phone published or proved, or still has in flight.
    if (journal != null &&
        (journal.pendingMove != null || journal.verifiedTarget != null)) {
      return false;
    }
    if (PublishStateBackup.gitHubRecordHoldsSite(phone.gitHubRecord) ||
        phone.cloudflareRecord.target != null ||
        phone.cloudflareAttempt.target != null) {
      return false;
    }
    // 2. A host this phone chose must be the backup's host.
    final activeHere = journal?.activeHost;
    if (activeHere != null && activeHere != archived.effectiveActiveHost) {
      return false;
    }
    // 3. Every connection this phone has must point at the backup's site.
    final site = archived.activeSite;
    for (final connected in <PublishTarget?>[
      phone.gitHubConnection,
      phone.cloudflareConnection,
    ]) {
      if (connected == null) continue;
      if (site == null || !site.isSameExactTarget(connected)) return false;
    }
    return true;
  }
}
