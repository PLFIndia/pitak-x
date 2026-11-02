/// What one section contributes to a publish (publish domain, pure Dart;
/// Cloudflare plan R3/R7).
///
/// A section is the unit of OWNERSHIP: the catalogue owns `books.json`,
/// `index.html`, `library.json` and `covers/*`; events own `events.html`,
/// `events.json` and `posters/*`; availability owns `availability.json`
/// (ADR 0019). Merging is section-scoped (R7), so a section's builder can
/// never delete another section's files.
library;

import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
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

  /// The availability fast lane (ADR 0019): exactly `availability.json`,
  /// the list of items whose every copy is lent out.
  availability;

  /// True when ANY section owns [path], i.e. it is one of Pitak's own public
  /// files.
  ///
  /// This is the one "is this an app-owned path?" rule. Records, move plans
  /// and Cloudflare snapshots all ask it, so adding a section here (as
  /// ADR 0019 did) can never leave one of them refusing the new file.
  /// Before S2 that rule was copied into three files.
  static bool anyOwns(String path) =>
      SiteSection.values.any((section) => section.owns(path));
}

/// The app-owned paths each section may write or delete (R7/R13). Exact
/// prefixes and file names only — never a blind head-tree sweep.
extension SiteSectionOwnership on SiteSection {
  /// True when [path] belongs to this section.
  ///
  /// `index.html` is the one path two sections share: the catalogue writes
  /// the viewer page there, and a retired site replaces it with the moved
  /// page. They never publish together, because retirement replaces the
  /// whole site.
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
      // One exact file name, never a prefix: the lane must not be able to
      // touch anything else on the site.
      SiteSection.availability => path == AvailabilityDocument.path,
    };
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

  /// True when publishing this section would change the site: a file to
  /// upload or a path to delete. An unchanged file is carried by its sha and
  /// uploads nothing, so a section without either is already published.
  ///
  /// The availability publishes on both hosts use this to send nothing for
  /// an unchanged set (ADR 0019): on GitHub an empty commit would still cost
  /// a Pages build, on Cloudflare a deploy would still cost about 20 API
  /// calls and a new version.
  bool get changesSite => hasUploads || deletePaths.isNotEmpty;
}
