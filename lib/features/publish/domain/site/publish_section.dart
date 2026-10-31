/// What one section contributes to a publish (publish domain, pure Dart;
/// Cloudflare plan R3/R7).
///
/// A section is the unit of OWNERSHIP: the catalogue owns `books.json`,
/// `index.html`, `library.json` and `covers/*`; events own `events.html`,
/// `events.json` and `posters/*`. Merging is section-scoped (R7), so a
/// section's builder can never delete the other section's files.
library;

import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// Which part of the site a [PublishSection] owns.
enum SiteSection {
  /// The catalogue: books.json, the viewer page, covers and the descriptor.
  catalogue,

  /// Announcements and events: events.html, events.json and posters.
  events,

  /// The moved page a retired site keeps (index.html + 404.html + marker).
  retirement,
}

/// The app-owned paths each section may write or delete (R7/R13). Exact
/// prefixes and file names only — never a blind head-tree sweep.
extension SiteSectionOwnership on SiteSection {
  /// True when [path] belongs to this section (and only this section).
  bool owns(String path) {
    if (!SitePath.isValid(path)) return false;
    return switch (this) {
      SiteSection.catalogue =>
        path == 'books.json' ||
            path == 'index.html' ||
            path == 'library.json' ||
            path.startsWith('covers/'),
      SiteSection.events =>
        path == 'events.html' ||
            path == 'events.json' ||
            path.startsWith('posters/'),
      // The moved page: two HTML files plus the freshness marker.
      SiteSection.retirement =>
        path == 'index.html' ||
            path == '404.html' ||
            path == 'pitak-publish.json',
    };
  }

  /// Every owned path in [paths], in order, de-duplicated.
  List<String> ownedOf(Iterable<String> paths) {
    final seen = <String>{};
    return [
      for (final path in paths)
        if (owns(path) && seen.add(path)) path,
    ];
  }
}

/// True when [path] is a safe relative publish path (exposed for the merge
/// tests and hosts that validate before writing).
///
/// Since S5 this is the shared [SitePath] policy and nothing else: the check
/// that used to live here was a second, weaker copy of it (Cloudflare plan
/// R23 — one path rule for both hosts).
bool isSafePublishPath(String path) => SitePath.isValid(path);

/// One built section, ready for a host adapter.
final class PublishSection {
  /// Creates a section.
  const PublishSection({
    required this.section,
    required this.files,
    this.deletePaths = const [],
    this.coverUrlByKey = const {},
  });

  /// Which part of the site this is.
  final SiteSection section;

  /// Files to write, in a deterministic order.
  final List<PublishFile> files;

  /// App-owned paths this section no longer publishes and the host must
  /// delete (e.g. an opted-out `library.json`, a removed poster).
  final List<String> deletePaths;

  /// Cover-source bookkeeping: decider key (`<itemId>` or
  /// `periodical:<uid>`) → the cover SOURCE URL this publish decided from.
  /// The manifest stores it so the remote-cover identity skip survives.
  final Map<String, String> coverUrlByKey;

  /// Every path this section writes.
  List<String> get paths => [for (final f in files) f.path];

  /// True when any file needs its bytes uploaded.
  bool get hasUploads => files.any((f) => f.upload);
}
