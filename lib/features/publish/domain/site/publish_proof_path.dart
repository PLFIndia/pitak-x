/// Which public file proves that a GitHub commit is being served (publish
/// domain, pure Dart; ADR 0019 Decision 10, plan AV12, A.6 #21).
///
/// Why this exists (beginner note): after a commit, GitHub Pages rebuilds the
/// site, and the app proves the new version is live by reading back a file
/// that commit CHANGED. Until now the check always read a fixed file per
/// section — `books.json` for the catalogue, `events.json` for events. That
/// has a gap (plan A.1 item 8): after an unconfirmed events commit, a
/// catalogue publish reads `books.json`, which the events commit never
/// touched, and "proves" the events commit live from unchanged bytes.
///
/// So every GitHub record now stores the proof of ITS last commit ("its
/// hash" = the hash this phone recorded for that file):
///
/// | Commit | Proof | Expected |
/// |---|---|---|
/// | catalogue (with or without availability) | `books.json` | its hash |
/// | events | `events.json` | its hash |
/// | availability | `availability.json` | its hash |
/// | availability removal | `availability.json` | an exact HTTP 404 |
///
/// The last row is why a path alone is not enough: a removal is proven by
/// the file being GONE (`expectsAbsent`).
///
/// A record without a proof (written before ADR 0019) reads as null, and the
/// check keeps using today's per-section file for it.
///
/// Cloudflare records need no proof path: every Cloudflare deploy writes a
/// marker with a fresh id, and the marker proves the whole atomic version
/// (ADR 0017 Decision 6; plan A.6 #25).
library;

import 'package:pitaka/features/publish/domain/availability/availability_document.dart';

/// The proof of a record's last commit. Stored by [name], like
/// `PublishState`.
enum PublishProofPath {
  /// A catalogue commit, including a combined catalogue + availability one:
  /// `books.json` changes on every catalogue publish (`exportedAt`).
  booksJson('books.json', expectsAbsent: false),

  /// An events commit.
  eventsJson('events.json', expectsAbsent: false),

  /// An availability-only commit.
  availabilityJson(AvailabilityDocument.path, expectsAbsent: false),

  /// The removal of `availability.json` (the lane was switched off).
  availabilityJsonAbsent(AvailabilityDocument.path, expectsAbsent: true);

  const PublishProofPath(this.path, {required this.expectsAbsent});

  /// The site-relative file to read back.
  final String path;

  /// True when the commit is proven by an exact 404 for [path]; false when
  /// it is proven by [path] serving its recorded hash.
  final bool expectsAbsent;

  /// The value stored as [raw], or null when [raw] is not one of these names.
  static PublishProofPath? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  /// True when a record's file map ([fileShas]: path → hash) agrees with this
  /// proof: an expected file is recorded, an expected absence is not.
  ///
  /// A proof that disagrees with its own record cannot prove anything, so the
  /// record treats it as unreadable (`PublishManifest.fromJson`).
  bool agreesWith(Map<String, String> fileShas) {
    final recorded = fileShas.containsKey(path);
    return expectsAbsent ? !recorded : recorded;
  }
}
