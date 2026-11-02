/// The phone's publishing record as it travels inside a backup (publish
/// domain, pure Dart; plan CV6/CV7, ADR 0020 Decision 7, ADR 0014
/// amendment of 2026-11-02).
///
/// Why a backup carries it (beginner note): cover file names on the website
/// are a salted hash of each item's id, and the salt lived only on the phone.
/// A new phone made a new salt, so its first publish renamed — and
/// re-uploaded — every cover, and left the old copies behind as clutter. With
/// the salt and the two publish records inside the backup, a restored phone
/// computes the SAME names and knows what is already online, so it uploads
/// nothing that is already there.
///
/// What it holds: the cover salt (16 bytes; not a secret — it only hides
/// internal ids, plan D.3), the GitHub record, the Cloudflare record, and the
/// host journal's active host and verified address. What it never holds:
/// tokens or any credential, a pending move, the unconfirmed Cloudflare
/// attempt, the GitHub upload journal and the availability lane's store —
/// in-flight work belongs to the phone that started it (plan CV6, A.6 #108).
///
/// Everything here is already public on the published site except the salt
/// and the Cloudflare account id (an identifier, not a credential).
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// A validated publishing record read from, or written to, a backup.
final class PublishStateBackup {
  const PublishStateBackup._({
    required this.coverSalt,
    required this.gitHubRecord,
    required this.cloudflareRecord,
    required this.activeHost,
    required this.verifiedTarget,
  });

  /// The length of every cover salt (16 bytes).
  static const int saltLength = 16;

  /// Builds the value, or null when it is not one a phone could adopt:
  ///  - the salt is not exactly [saltLength] bytes (0–255 each);
  ///  - a verified address belongs to another host than [activeHost] (the
  ///    host journal's own consistency rule, `PublishHostState.isConsistent`);
  ///  - it describes no site at all (nothing to adopt, so nothing is worth a
  ///    backup entry).
  static PublishStateBackup? tryCreate({
    required List<int> coverSalt,
    PublishManifest gitHubRecord = PublishManifest.empty,
    CloudflareSiteManifest cloudflareRecord = CloudflareSiteManifest.empty,
    PublishHost? activeHost,
    PublishTarget? verifiedTarget,
  }) {
    if (coverSalt.length != saltLength ||
        coverSalt.any((byte) => byte < 0 || byte > 255)) {
      return null;
    }
    if (verifiedTarget != null && verifiedTarget.host != activeHost) {
      return null;
    }
    final value = PublishStateBackup._(
      coverSalt: List.unmodifiable(coverSalt),
      gitHubRecord: gitHubRecord,
      cloudflareRecord: cloudflareRecord,
      activeHost: activeHost,
      verifiedTarget: verifiedTarget,
    );
    return value.describesASite ? value : null;
  }

  /// The salt every cover name and public item key is derived from.
  final List<int> coverSalt;

  /// What the phone published to GitHub ([PublishManifest.empty] if nothing).
  final PublishManifest gitHubRecord;

  /// What the phone published to Cloudflare (empty if nothing).
  final CloudflareSiteManifest cloudflareRecord;

  /// The host the library published to, or null when the phone's journal
  /// had none (an older GitHub-only phone: its record alone names GitHub).
  final PublishHost? activeHost;

  /// The site a read-back PROVED was serving the library, or null.
  final PublishTarget? verifiedTarget;

  /// True when some record or the journal names a site.
  bool get describesASite =>
      gitHubRecordHoldsSite(gitHubRecord) ||
      cloudflareRecord.target != null ||
      verifiedTarget != null;

  /// The host this library publishes to: the journal's, else GitHub when
  /// only a GitHub record exists — the same legacy default the phone applies
  /// to a missing journal (`PublishHostStateRepository`).
  PublishHost? get effectiveActiveHost =>
      activeHost ??
      (GitHubPublishTarget.create(gitHubRecord.repo) != null
          ? PublishHost.github
          : null);

  /// The site this library publishes to: the verified address when it is on
  /// [effectiveActiveHost], else the active host's record target.
  PublishTarget? get activeSite {
    final host = effectiveActiveHost;
    if (host == null) return null;
    final verified = verifiedTarget;
    if (verified != null && verified.host == host) return verified;
    return switch (host) {
      PublishHost.github => GitHubPublishTarget.create(gitHubRecord.repo),
      PublishHost.cloudflare => cloudflareRecord.target,
    };
  }

  /// The same value, with both records keeping LOCAL cover sources only for
  /// the cover files in [carriedLeaves] — the covers the same backup carried
  /// (ADR 0020 Decision 7, plan S11). A source naming any other local file
  /// is forgotten, so the next publish reads that cover again.
  PublishStateBackup withLocalCoverSourcesFor(Set<String> carriedLeaves) =>
      PublishStateBackup._(
        coverSalt: coverSalt,
        gitHubRecord: gitHubRecord.withoutLocalCoverSources(
          exceptLeaves: carriedLeaves,
        ),
        cloudflareRecord: cloudflareRecord.withoutLocalCoverSources(
          exceptLeaves: carriedLeaves,
        ),
        activeHost: activeHost,
        verifiedTarget: verifiedTarget,
      );

  /// True when [record] names a GitHub site: a repository, a head or a path.
  static bool gitHubRecordHoldsSite(PublishManifest record) =>
      record.repo != null ||
      record.headSha != null ||
      record.fileShas.isNotEmpty;

  /// Never prints the salt (not a secret, but nothing gains from logging it).
  @override
  String toString() =>
      'PublishStateBackup($gitHubRecord, $cloudflareRecord, '
      '${activeHost?.name}, ${verifiedTarget?.targetId})';
}
