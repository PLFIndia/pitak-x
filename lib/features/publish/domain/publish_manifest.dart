/// Incremental-publish manifest (pure domain, AGENTS.md §3.1, #32).
///
/// Port of Kotlin `PublishManifest`. On-device record of what we last published
/// so the next publish skips unchanged files. PUBLIC data only — repo paths,
/// git blob shas, public cover URLs — so it needs no encryption. It is a CACHE,
/// never the source of truth: if missing/stale, the flow rebuilds it from the
/// repo's real git tree, so a wrong manifest can only cause a redundant upload,
/// never a wrong/missing file on the page.
///
/// Keyed to the target `repo` ("owner/name") so switching repos never reuses
/// the wrong shas.
library;

/// What was last published, for incremental diffing.
final class PublishManifest {
  /// Creates a manifest.
  const PublishManifest({
    this.repo,
    this.fileShas = const {},
    this.coverUrlByBookId = const {},
  });

  /// Parses a manifest from [json]; tolerant (bad shapes → empty maps).
  factory PublishManifest.fromJson(Map<String, dynamic> json) {
    Map<String, String> strMap(Object? o) => o is Map
        ? {
            for (final e in o.entries)
              if (e.value is String) '${e.key}': e.value as String,
          }
        : const {};
    return PublishManifest(
      repo: json['repo'] as String?,
      fileShas: strMap(json['fileShas']),
      coverUrlByBookId: strMap(json['coverUrlByBookId']),
    );
  }

  /// The empty manifest (forces a full, correct publish).
  static const PublishManifest empty = PublishManifest();

  /// "owner/name" this manifest describes; null in the empty manifest.
  final String? repo;

  /// Published file path → git blob sha last uploaded for it.
  final Map<String, String> fileShas;

  /// Book id (as string) → the `coverUrl` value at last publish. Drives the
  /// source-identity skip for REMOTE covers.
  final Map<String, String> coverUrlByBookId;

  /// The last-published sha for [path], or null.
  String? shaFor(String path) => fileShas[path];

  /// JSON map.
  Map<String, dynamic> toJson() => {
    if (repo != null) 'repo': repo,
    'fileShas': fileShas,
    'coverUrlByBookId': coverUrlByBookId,
  };
}
