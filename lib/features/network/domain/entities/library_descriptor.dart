/// The parsed `library.json` — a library's PUBLISHED network descriptor
/// (network domain, pure Dart; docs/ARCHITECTURE.md §5.1, schema 1).
///
/// This is what every Pitak site publishes next to `books.json`: a public
/// self-description carrying the library's fingerprint (never the raw ID,
/// D3), name, site URL, an opted-in location, and its hub/member relations.
/// Two roles read it:
///  - OUR site WRITES it at publish time (`BuildOwnDescriptor` +
///    `LibraryDescriptorCodec.encode`);
///  - every device READS the descriptors of the libraries it saved
///    (`RefreshNetworkUseCase`, via the bounded descriptor fetcher).
///
/// The wire rules (required fields, bounds, truncation) live in
/// `LibraryDescriptorCodec` — this file is only the immutable data shape.
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// One member listed inside a hub's descriptor (§3.1 `members[]`).
///
/// [name] is optional on the wire (a hub may not have stored it), hence
/// nullable; [fingerprint] and [siteUrl] are always present and validated by
/// the codec before a `MemberEntry` exists.
final class MemberEntry {
  /// Creates a member entry from already-validated parts.
  const MemberEntry({
    required this.fingerprint,
    required this.siteUrl,
    this.name,
  });

  /// The member's published fingerprint (64 lowercase hex, §3.3).
  final String fingerprint;

  /// The member's published site URL (`BookmarkUrl`-normalized).
  final String siteUrl;

  /// Display name when the publishing hub carried one; may be null.
  final String? name;
}

/// A validated `library.json` document (schema 1).
///
/// Invariant kept by every producer (codec decode, `BuildOwnDescriptor`):
/// [location] and [precision] are set TOGETHER or both null — a coordinate
/// without its declared precision must never be published or rendered, so the
/// codec's encoder drops the whole block when either is missing (fail closed
/// on privacy).
final class LibraryDescriptor {
  /// Creates a descriptor from already-validated parts.
  const LibraryDescriptor({
    required this.fingerprint,
    required this.name,
    required this.siteUrl,
    required this.updatedAt,
    this.location,
    this.precision,
    this.members = const [],
    this.memberOf = const [],
  });

  /// This library's fingerprint (§3.3) — its published identity.
  final String fingerprint;

  /// Display name (`NetworkName`-validated: trimmed 1–80, no control/bidi).
  final String name;

  /// Published site root URL (`BookmarkUrl`-normalized, ends with `/`).
  final String siteUrl;

  /// Epoch milliseconds of the publish that produced this file.
  final int updatedAt;

  /// Opted-in public location, or null when the library shares none.
  final GeoPoint? location;

  /// Declared precision of [location]; null exactly when [location] is null.
  final LocationPrecision? precision;

  /// Members this library (as a hub) added by card scan; ≤ 200 (codec cap).
  final List<MemberEntry> members;

  /// Hub site URLs this library says it is a member of; ≤ 20 (codec cap).
  final List<String> memberOf;

  /// Field-by-field equality of everything EXCEPT [updatedAt] — the "did the
  /// published content actually change?" question the publish sha-skip asks
  /// (review Lows: a fresh timestamp every publish defeated it). Both sides
  /// are codec-canonical (members/memberOf sorted at encode time), so list
  /// order comparison is exact, not accidental.
  bool samePublishedContentAs(LibraryDescriptor other) =>
      other.fingerprint == fingerprint &&
      other.name == name &&
      other.siteUrl == siteUrl &&
      other.precision == precision &&
      _sameLocation(location, other.location) &&
      _sameMembers(members, other.members) &&
      _sameStrings(memberOf, other.memberOf);

  /// A copy with a different [updatedAt] — the publish pipeline reuses the
  /// live file's timestamp when [samePublishedContentAs] says nothing
  /// changed, so the encoded bytes (and blob sha) stay stable.
  LibraryDescriptor withUpdatedAt(int updatedAt) => LibraryDescriptor(
    fingerprint: fingerprint,
    name: name,
    siteUrl: siteUrl,
    updatedAt: updatedAt,
    location: location,
    precision: precision,
    members: members,
    memberOf: memberOf,
  );

  static bool _sameLocation(GeoPoint? a, GeoPoint? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.sameAs(b);
  }

  static bool _sameMembers(List<MemberEntry> a, List<MemberEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.fingerprint != y.fingerprint ||
          x.siteUrl != y.siteUrl ||
          x.name != y.name) {
        return false;
      }
    }
    return true;
  }

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
