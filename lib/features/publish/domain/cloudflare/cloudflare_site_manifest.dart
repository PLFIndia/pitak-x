/// The on-device record of what this phone published to one Cloudflare Worker
/// (publish domain, pure Dart; Cloudflare plan R5/R7/E.5).
///
/// Why it exists (beginner note): a Cloudflare deploy is a COMPLETE snapshot —
/// the Worker serves exactly the asset set of the newest version. So the record
/// answers two questions the next publish cannot answer from the network:
///  - which paths this phone wrote (so a section update can carry the other
///    section forward instead of dropping it), and
///  - which Cloudflare asset hash each path had (so an unchanged file is not
///    re-uploaded, and a hash the API asks for can be served from the spool).
///
/// It is NOT a cache. A record that does not describe the exact target claims
/// nothing: `describes` must match the account, the Worker and the derived
/// address, or the file map is discarded. Claiming another Worker's paths would
/// let a publish delete files this phone never wrote (R12/R13).
///
/// `hashScheme` is the safety valve for the asset-hash formula (B.7): a record
/// written by a build with a different formula keeps its paths but not its
/// hashes — the bytes are re-hashed, and bytes that are gone send the publish
/// into replacement reconciliation instead of a permanent missing-hash loop.
///
/// PUBLIC data only — paths, content hashes, sizes, content types and public
/// cover URLs. No token, no JWT, no account secret.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// One published asset's metadata.
final class CloudflareAssetEntry {
  /// Creates an entry.
  const CloudflareAssetEntry({
    required this.sha,
    required this.hash,
    required this.size,
    required this.type,
  });

  /// The host-neutral content identity (git blob sha), shared with the section
  /// merge and the snapshot digest.
  final String sha;

  /// The Cloudflare asset hash (see [CloudflareAssetHash]).
  final String hash;

  /// Byte length of the file.
  final int size;

  /// The exact content type it is served with.
  final CloudflareContentType type;

  /// Encodes this entry (public data only).
  Map<String, Object?> toJson() => {
    'sha': sha,
    'hash': hash,
    'size': size,
    'type': type.header,
  };

  /// Decodes an entry, or null when any field is missing or unknown.
  ///
  /// A wrong type is a corrupt record, not a crash: the caller treats null as
  /// "no usable entry" and re-hashes or reconciles.
  static CloudflareAssetEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sha = raw['sha'];
    final hash = raw['hash'];
    final size = raw['size'];
    final type = CloudflareContentType.forHeader(
      raw['type'] is String ? raw['type'] as String : null,
    );
    if (sha is! String || sha.isEmpty) return null;
    if (hash is! String || !_isAssetHash(hash)) return null;
    if (size is! int || size < 0 || size > CloudflareLimits.maxFileBytes) {
      return null;
    }
    if (type == null) return null;
    return CloudflareAssetEntry(sha: sha, hash: hash, size: size, type: type);
  }

  @override
  String toString() => 'CloudflareAssetEntry($sha, $hash, $size)';
}

/// The result of merging one section into a Cloudflare snapshot.
final class CloudflareMergeResult {
  /// Creates the result.
  const CloudflareMergeResult({
    required this.files,
    required this.missingHashes,
  });

  /// The complete next Worker snapshot: path → entry.
  final Map<String, CloudflareAssetEntry> files;

  /// Paths the snapshot needs but has no trusted hash for.
  ///
  /// Non-empty means the caller must re-hash the bytes it can still read, and
  /// if any remain, stop before deploy and reconcile (R5/R23). It is never
  /// "publish without them".
  final List<String> missingHashes;
}

/// What was last published to one Cloudflare Worker.
final class CloudflareSiteManifest implements PreviousPublication {
  /// Creates a manifest. The default is the EMPTY record: no target, no claim.
  const CloudflareSiteManifest({
    this.schema = currentSchema,
    this.target,
    this.state = PublishState.deployed,
    this.publishId,
    this.liveId,
    this.hashScheme,
    this.files = const {},
    this.coverUrlByBookId = const {},
  });

  /// Decodes a record, or the EMPTY record when it does not describe a target.
  ///
  /// Fails closed on purpose: without a target the file map is meaningless (it
  /// could authorise deleting another Worker's files), so a record whose target
  /// cannot be rebuilt claims nothing at all.
  factory CloudflareSiteManifest.fromJson(Map<String, dynamic> json) {
    final target = _targetFrom(json['target']);
    if (target == null || json['schema'] != currentSchema) return empty;
    final state = _stateFrom(json['state']);
    final publishId = json['publishId'];
    if (state == null ||
        publishId is! String ||
        !PublishMarker.isValidPublishId(publishId)) {
      return empty;
    }

    // A partial file map is not a usable record. If one entry is corrupt, the
    // whole map loses its ownership/freshness meaning and the next publish must
    // reconcile explicitly instead of omitting that path from a full deploy.
    final rawFiles = json['files'];
    if (rawFiles is! Map ||
        rawFiles.length > CloudflareLimits.maxFilesPerVersion) {
      return empty;
    }
    final files = <String, CloudflareAssetEntry>{};
    for (final entry in rawFiles.entries) {
      final rawPath = entry.key;
      if (rawPath is! String) return empty;
      final path = SitePath.tryParse(rawPath);
      final asset = CloudflareAssetEntry.fromJson(entry.value);
      if (path == null ||
          !isAllowedPath(rawPath) ||
          asset == null ||
          asset.type != CloudflareContentType.forPath(path)) {
        return empty;
      }
      files[rawPath] = asset;
    }
    if (!isValidFileSet(state: state, paths: files.keys)) return empty;
    return CloudflareSiteManifest(
      target: target,
      state: state,
      publishId: publishId,
      liveId: json['liveId'] is String ? json['liveId'] as String : null,
      hashScheme: json['hashScheme'] is String
          ? json['hashScheme'] as String
          : null,
      files: Map.unmodifiable(files),
      coverUrlByBookId: _stringMap(json['coverUrlByBookId']),
    );
  }

  /// The schema this build writes.
  static const int currentSchema = 2;

  /// The empty manifest (nothing recorded on this phone).
  static const CloudflareSiteManifest empty = CloudflareSiteManifest();

  /// True only for Pitak's fixed public files and reserved asset namespaces.
  /// Unknown paths are never adopted into a complete Worker snapshot (R12/R23).
  static bool isAllowedPath(String path) =>
      SiteSection.catalogue.owns(path) ||
      SiteSection.events.owns(path) ||
      SiteSection.retirement.owns(path);

  /// Validates the file-set invariant for the recorded deployment kind.
  ///
  /// A normal deployment always has the marker and catalogue core; events HTML
  /// and JSON arrive together. A retired deployment is exactly the moved page,
  /// its 404 page, and the retired marker. This prevents a syntactically valid
  /// but semantically mixed record from feeding freshness or section merging.
  static bool isValidFileSet({
    required PublishState state,
    required Iterable<String> paths,
  }) {
    final set = paths.toSet();
    if (set.length != paths.length) return false;
    if (state == PublishState.retired) {
      return set.length == 3 &&
          set.contains('index.html') &&
          set.contains('404.html') &&
          set.contains(CloudflareLimits.markerPath);
    }
    if (!set.contains('books.json') ||
        !set.contains('index.html') ||
        !set.contains(CloudflareLimits.markerPath) ||
        set.contains('404.html')) {
      return false;
    }
    final hasEventsHtml = set.contains('events.html');
    final hasEventsJson = set.contains('events.json');
    if (hasEventsHtml != hasEventsJson) return false;
    final hasPosters = set.any((path) => path.startsWith('posters/'));
    return !hasPosters || hasEventsJson;
  }

  /// Schema of the record this object was read from.
  final int schema;

  /// The exact Worker this record describes; null in the empty record.
  final CloudflarePublishTarget? target;

  /// How far the recorded deploy has been proven (R5).
  final PublishState state;

  /// The `publishId` of the marker this record's deploy wrote.
  final String? publishId;

  /// Optional deployment id — diagnostics only, never load-bearing (B.4).
  final String? liveId;

  /// The asset-hash formula the recorded hashes were computed with.
  final String? hashScheme;

  /// Published path → asset metadata.
  final Map<String, CloudflareAssetEntry> files;

  /// Book id (as string) → the `coverUrl` value at last publish.
  final Map<String, String> coverUrlByBookId;

  /// True when the recorded hashes were computed with this build's formula.
  ///
  /// False means the hashes are unusable, NOT that the paths are unknown: the
  /// paths still say which files this phone wrote (R5).
  bool get hashesTrusted => hashScheme == CloudflareAssetHash.scheme;

  /// The record when it describes [target] and its file set is valid;
  /// otherwise the EMPTY record.
  ///
  /// This is the one rule for "what does my record claim?" (handoff §13): a
  /// record for another target claims NOTHING. It must never be an error,
  /// because a user who reconnected to another Worker would otherwise be
  /// stranded with no way to publish (fix-plan H1).
  CloudflareSiteManifest forTarget(CloudflarePublishTarget target) =>
      describes(target) && isValidFileSet(state: state, paths: ownedPaths)
      ? this
      : empty;

  /// True when this record describes exactly [other].
  bool describes(CloudflarePublishTarget other) {
    final mine = target;
    if (mine == null) return false;
    return mine.targetId == other.targetId && mine.siteUrl == other.siteUrl;
  }

  /// The recorded entry for [path], or null.
  CloudflareAssetEntry? entryFor(String path) => files[path];

  /// The content sha recorded for [path], or null (the builders' view).
  @override
  String? shaFor(String path) => files[path]?.sha;

  /// The cover source URL recorded for [key], or null.
  @override
  String? coverSourceFor(String key) => coverUrlByBookId[key];

  /// Every app-owned path this record claims.
  @override
  Iterable<String> get ownedPaths => files.keys;

  /// The record to persist right after a deploy landed.
  ///
  /// [files] is the COMPLETE snapshot the deploy sent — a Cloudflare deploy
  /// replaces the whole asset set, so a partial map would be a lie.
  CloudflareSiteManifest afterDeploy({
    required String publishId,
    required Map<String, CloudflareAssetEntry> files,
    required Map<String, String> coverUrlByBookId,
  }) => CloudflareSiteManifest(
    target: target,
    publishId: publishId,
    liveId: liveId,
    hashScheme: CloudflareAssetHash.scheme,
    files: files,
    coverUrlByBookId: coverUrlByBookId,
  );

  /// The same record, now proven to be served by the live site.
  CloudflareSiteManifest asLive() => _copy(state: PublishState.live);

  /// The same record after the site became a moved page.
  ///
  /// A retirement deploy is a fresh deploy with a fresh publish id and only the
  /// moved files, so the file map is replaced, not merged (F.6).
  CloudflareSiteManifest asRetired({
    required String publishId,
    required Map<String, CloudflareAssetEntry> files,
  }) => CloudflareSiteManifest(
    target: target,
    state: PublishState.retired,
    publishId: publishId,
    liveId: liveId,
    hashScheme: CloudflareAssetHash.scheme,
    files: files,
    coverUrlByBookId: coverUrlByBookId,
  );

  /// Merges one section into this record, producing the complete next snapshot.
  ///
  /// [merge] is the SHARED section merge (R7) — the same one GitHub uses — so
  /// the path rules cannot diverge. [built] holds the entries for the files the
  /// section just built; every other path in [merge] is carried from this
  /// record, but only when its recorded sha still matches and its hashes are
  /// trusted. Anything else is reported in `missingHashes` rather than guessed.
  CloudflareMergeResult mergedWith({
    required SectionMerge merge,
    required Map<String, CloudflareAssetEntry> built,
  }) {
    final next = <String, CloudflareAssetEntry>{};
    final missing = <String>[];
    for (final entry in merge.fileShas.entries) {
      final path = entry.key;
      final builtEntry = built[path];
      if (builtEntry != null) {
        next[path] = builtEntry;
        continue;
      }
      final previous = files[path];
      if (previous != null && hashesTrusted && previous.sha == entry.value) {
        next[path] = previous;
      } else {
        missing.add(path);
      }
    }
    missing.sort();
    return CloudflareMergeResult(files: next, missingHashes: missing);
  }

  /// Encodes this record. Public data only; no token, no credential.
  Map<String, Object?> toJson() => {
    'schema': schema,
    if (target case final target?) 'target': _targetJson(target),
    'state': state.name,
    if (publishId != null) 'publishId': publishId,
    if (liveId != null) 'liveId': liveId,
    if (hashScheme != null) 'hashScheme': hashScheme,
    'files': {
      for (final entry in files.entries) entry.key: entry.value.toJson(),
    },
    'coverUrlByBookId': coverUrlByBookId,
  };

  CloudflareSiteManifest _copy({required PublishState state}) =>
      CloudflareSiteManifest(
        schema: schema,
        target: target,
        state: state,
        publishId: publishId,
        liveId: liveId,
        hashScheme: hashScheme,
        files: files,
        coverUrlByBookId: coverUrlByBookId,
      );

  static Map<String, Object?> _targetJson(CloudflarePublishTarget target) => {
    'accountId': target.accountId.value,
    'workerName': target.workerName.value,
    'accountSubdomain': target.accountSubdomain.value,
    'siteUrl': target.siteUrl,
  };

  /// Rebuilds the target from its identity parts and refuses a stored URL that
  /// disagrees with the derived one (C3).
  static CloudflarePublishTarget? _targetFrom(Object? raw) {
    if (raw is! Map) return null;
    final target = CloudflarePublishTarget.create(
      accountId: raw['accountId'] is String ? raw['accountId'] as String : null,
      workerName: raw['workerName'] is String
          ? raw['workerName'] as String
          : null,
      accountSubdomain: raw['accountSubdomain'] is String
          ? raw['accountSubdomain'] as String
          : null,
    );
    if (target == null) return null;
    if (raw['siteUrl'] != target.siteUrl) return null;
    return target;
  }

  static Map<String, String> _stringMap(Object? raw) => raw is Map
      ? {
          for (final entry in raw.entries)
            if (entry.value is String) '${entry.key}': entry.value as String,
        }
      : const {};

  static PublishState? _stateFrom(Object? raw) {
    for (final value in PublishState.values) {
      if (value.name == raw) return value;
    }
    // An unknown state is NOT coerced to `deployed`: the caller discards the
    // WHOLE record, which is safer than trusting a file map this build cannot
    // classify (fix-plan N17).
    return null;
  }

  @override
  String toString() =>
      'CloudflareSiteManifest(${target?.targetId}, $state, '
      '${files.length} files)';
}

bool _isAssetHash(String value) => CloudflareAssetHash.isValidHash(value);
