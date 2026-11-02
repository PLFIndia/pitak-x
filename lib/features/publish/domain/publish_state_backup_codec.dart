/// The `publish_state.json` backup entry (publish domain, pure Dart; plan
/// CV6, ADR 0014 amendment of 2026-11-02, docs/ARCHITECTURE.md §5.5):
///
/// ```json
/// { "schemaVersion": 1,
///   "coverSalt": "<base64 of 16 bytes>",
///   "gitHubRecord": { <PublishManifest JSON> },
///   "cloudflareRecord": { <CloudflareSiteManifest JSON> },
///   "host": { "active": "github", "verifiedTarget": { <target JSON> } } }
/// ```
///
/// `gitHubRecord`, `cloudflareRecord`, `host` and `verifiedTarget` are left
/// out when there is nothing to say. The codec lives in the publish feature
/// (like `NetworkArchiveCodec` in the network feature) because the records'
/// shapes are this feature's contract; backup only stores the text.
///
/// Decode treats the archive as HOSTILE input (AGENTS.md §6.5): the text is
/// bounded in size and nesting depth before it is parsed, every field is
/// checked, and ONE bad field makes the whole entry unreadable (null). That
/// is the safe direction: a phone that adopts nothing simply publishes as a
/// new phone did before plan S11 — it uploads more, it never deletes or
/// claims a file it should not. In particular a GitHub record may only claim
/// Pitak's own path shapes (`SiteSection.anyOwns`) with real git shas, so a
/// crafted archive cannot make a publish delete a file a person wrote.
library;

import 'dart:convert';

import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/github_branch_name.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/publish_target_json.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// Encodes/decodes the `publish_state.json` entry.
abstract final class PublishStateBackupCodec {
  /// The newest entry schema this build writes and reads.
  static const int schemaVersion = 1;

  /// The largest entry (UTF-8 bytes) the backup reader decodes at all, and
  /// the largest the writer emits. A record holds at most 20,000 paths of
  /// about 100 bytes each, plus one cover source per item, so honest data
  /// stays far below this; the host journal uses the same bound.
  static const int maxBytes = 16 * 1024 * 1024;

  /// Deepest `{`/`[` nesting a valid entry can have (envelope → record →
  /// file map → asset entry is 4); anything deeper is refused unparsed.
  static const int maxJsonDepth = 8;

  /// The most paths a GitHub record may claim (Cloudflare's own decoder
  /// applies the same number, `CloudflareLimits.maxFilesPerVersion`).
  static const int maxRecordFiles = CloudflareLimits.maxFilesPerVersion;

  /// The most cover sources a record may carry (two per catalogue row at the
  /// 100,000-row catalogue cap: items and periodical titles).
  static const int maxCoverSources = 200000;

  /// The longest cover-source key and value accepted.
  static const int maxCoverKeyLength = 256;

  /// See [maxCoverKeyLength].
  static const int maxCoverSourceLength = 4096;

  static final RegExp _sha = RegExp(r'^[0-9a-f]{40}$');

  /// Encodes [state] as the entry's content.
  static String encode(PublishStateBackup state) {
    final host = state.activeHost;
    final verified = state.verifiedTarget;
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'coverSalt': base64Encode(state.coverSalt),
      if (PublishStateBackup.gitHubRecordHoldsSite(state.gitHubRecord))
        'gitHubRecord': state.gitHubRecord.toJson(),
      if (state.cloudflareRecord.target != null)
        'cloudflareRecord': state.cloudflareRecord.toJson(),
      if (host != null)
        'host': {
          'active': host.name,
          if (verified != null)
            'verifiedTarget': PublishTargetJson.encode(verified),
        },
    });
  }

  /// Parses the entry's content, or null when ANY part is unusable (see the
  /// library comment). Never throws.
  static PublishStateBackup? decode(String text) {
    if (text.length > maxBytes) return null;
    if (JsonNestingDepth.maxDepthOf(text) > maxJsonDepth) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['schemaVersion'] != schemaVersion) return null;

    final salt = _salt(decoded['coverSalt']);
    if (salt == null) return null;

    var gitHub = PublishManifest.empty;
    if (decoded.containsKey('gitHubRecord')) {
      final record = _gitHubRecord(decoded['gitHubRecord']);
      if (record == null) return null;
      gitHub = record;
    }

    var cloudflare = CloudflareSiteManifest.empty;
    if (decoded.containsKey('cloudflareRecord')) {
      final record = _cloudflareRecord(decoded['cloudflareRecord']);
      if (record == null) return null;
      cloudflare = record;
    }

    PublishHost? active;
    PublishTarget? verified;
    if (decoded.containsKey('host')) {
      final host = decoded['host'];
      if (host is! Map<String, dynamic>) return null;
      active = PublishTargetJson.hostFrom(host['active']);
      if (active == null) return null;
      if (host.containsKey('verifiedTarget')) {
        verified = PublishTargetJson.decode(
          host['verifiedTarget'],
          expectedHost: active,
        );
        if (verified == null) return null;
      }
    }

    return PublishStateBackup.tryCreate(
      coverSalt: salt,
      gitHubRecord: gitHub,
      cloudflareRecord: cloudflare,
      activeHost: active,
      verifiedTarget: verified,
    );
  }

  static List<int>? _salt(Object? raw) {
    if (raw is! String || raw.length > 64) return null;
    try {
      final bytes = base64Decode(raw);
      return bytes.length == PublishStateBackup.saltLength ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  /// A GitHub record checked field by field BEFORE `PublishManifest.fromJson`
  /// (which is lenient by design for this phone's own file): a repository
  /// and branch the app could publish to, a 40-hex head, Pitak-owned paths
  /// with 40-hex shas, a known state and bounded cover sources.
  static PublishManifest? _gitHubRecord(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final repo = raw['repo'];
    if (repo is! String || GitHubPublishTarget.create(repo) == null) {
      return null;
    }
    if (raw.containsKey('branch') &&
        GitHubBranchName.tryParse(_string(raw['branch'])) == null) {
      return null;
    }
    if (raw.containsKey('headSha') && !_isSha(raw['headSha'])) return null;
    if (raw.containsKey('ownershipConfirmed') &&
        raw['ownershipConfirmed'] is! bool) {
      return null;
    }
    if (raw.containsKey('state') && _state(raw['state']) == null) return null;
    if (!_ownedFiles(raw['fileShas'])) return null;
    if (!_coverSources(raw['coverUrlByBookId'])) return null;
    return PublishManifest.fromJson(raw);
  }

  /// A Cloudflare record: its own decoder is already strict (any bad field
  /// gives the EMPTY record), so an entry that decodes to no target is
  /// refused here instead of being adopted as "nothing".
  static CloudflareSiteManifest? _cloudflareRecord(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    if (!_coverSources(raw['coverUrlByBookId'])) return null;
    final record = CloudflareSiteManifest.fromJson(raw);
    return record.target == null ? null : record;
  }

  static bool _ownedFiles(Object? raw) {
    if (raw == null) return true;
    if (raw is! Map || raw.length > maxRecordFiles) return false;
    for (final entry in raw.entries) {
      final path = entry.key;
      if (path is! String ||
          SitePath.tryParse(path) == null ||
          !SiteSection.anyOwns(path) ||
          !_isSha(entry.value)) {
        return false;
      }
    }
    return true;
  }

  static bool _coverSources(Object? raw) {
    if (raw == null) return true;
    if (raw is! Map || raw.length > maxCoverSources) return false;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          key.isEmpty ||
          key.length > maxCoverKeyLength ||
          value is! String ||
          value.length > maxCoverSourceLength) {
        return false;
      }
    }
    return true;
  }

  static bool _isSha(Object? raw) => raw is String && _sha.hasMatch(raw);

  static PublishState? _state(Object? raw) {
    for (final state in PublishState.values) {
      if (state.name == raw) return state;
    }
    return null;
  }

  static String? _string(Object? raw) => raw is String ? raw : null;
}
