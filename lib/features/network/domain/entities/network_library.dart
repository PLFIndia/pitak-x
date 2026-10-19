/// One saved library on the network (network domain, pure Dart;
/// docs/ARCHITECTURE.md §5). The row the old bookmark was replaced by (ADR 0012).
///
/// A row is identified on the wire by its `fingerprint` (never the raw
/// library ID, D3) and on-device by `siteUrl` (the natural key — "the URL is
/// the identity", D13). Everything else is derived state refreshed from the
/// library's published `library.json`:
///  - `source` remembers how the row got here (migrated bookmark, card scan,
///    descriptor discovery);
///  - `isMember`/`memberVerified` describe the hub→member direction (I added
///    them by in-person card scan; a fetch confirmed the fingerprint);
///  - `membership` describes the member→hub direction (THIS row is a hub that
///    lists ME: pending user confirmation, confirmed, or declined);
///  - `confirmedByMember` is the reciprocal-consent signal for rows a hub
///    LISTED (design 2026-10-18): the member's own descriptor links back to
///    that hub in its `memberOf`. A hub's `members` entry is the hub's
///    claim; this flag is the member's published agreement with it;
///  - `fetchStatus` is the last refresh outcome, coarse, never carrying URLs.
///
/// Immutable; `id == 0` means "not saved yet". Pure Dart: no Flutter/IO/
/// Riverpod (AGENTS.md §3.1).
library;

import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';

/// How a network row got onto this device (D1).
enum NetworkSource {
  /// Migrated from the legacy bookmarks list, or added by URL.
  bookmark,

  /// Added by scanning the library's card QR in person.
  card,

  /// Found through another library's descriptor (hub or member list).
  discovered,
}

/// Am I a member of THIS row (which is a hub)? (docs/ARCHITECTURE.md §6 membership)
enum MembershipState {
  /// No signal either way.
  none,

  /// A fetched hub descriptor lists my fingerprint; the user has not answered
  /// the "show that I'm a member of X?" prompt yet.
  pending,

  /// The user confirmed the membership (published in my `memberOf`).
  confirmed,

  /// The user dismissed the prompt — never re-prompted unless they tap
  /// "Reconsider".
  declined,
}

/// Outcome of the last descriptor fetch for a row (coarse, §6).
enum FetchStatus {
  /// Never fetched.
  never,

  /// A valid descriptor arrived.
  ok,

  /// Transport-level refusal (host down, timeout, redirect trickery, …).
  unreachable,

  /// Bytes arrived but did not decode to a valid descriptor.
  invalid,

  /// The descriptor declares a schema newer than this build reads.
  schemaTooNew,

  /// The fetched fingerprint contradicts the saved one — NOT auto-merged,
  /// shown with a badge (D12, fail closed and visible).
  identityConflict,
}

/// An immutable network row. Constructed with validated-or-defaulted values;
/// the strict validation gate for HOSTILE input is [NetworkLibrary.fromJson].
final class NetworkLibrary {
  /// Creates a row. Values must already be valid ([siteUrl] normalized,
  /// [fingerprint] null or 64-hex, enums by definition) — `fromJson` and the
  /// repository mapping enforce that at the boundaries.
  const NetworkLibrary({
    required this.siteUrl,
    this.id = 0,
    this.name = '',
    this.fingerprint,
    this.location,
    this.precision,
    this.source = NetworkSource.bookmark,
    this.isMember = false,
    this.memberVerified = false,
    this.listedByHubUrl,
    this.membership = MembershipState.none,
    this.confirmedByMember = false,
    this.fetchStatus = FetchStatus.never,
    this.fetchedAt,
    this.createdAt = 0,
    this.sortOrder = 0,
  });

  /// Drift primary key; 0 = not saved yet.
  final int id;

  /// Published site root URL (`BookmarkUrl`-normalized; the natural key).
  final String siteUrl;

  /// Display name; '' until known.
  final String name;

  /// Published identity fingerprint, or null until a fetch/scan supplies it.
  final String? fingerprint;

  /// Opted-in public location, or null.
  final GeoPoint? location;

  /// Declared precision of [location]; null exactly when [location] is null.
  final LocationPrecision? precision;

  /// How this row got here.
  final NetworkSource source;

  /// I (as a hub) added this library by card scan.
  final bool isMember;

  /// A fetch confirmed the published fingerprint == the scanned one.
  final bool memberVerified;

  /// For discovered rows: which hub's descriptor listed this library.
  final String? listedByHubUrl;

  /// I am a member of THIS hub (pending/confirmed/declined/none).
  final MembershipState membership;

  /// Meaningful only when [listedByHubUrl] is set: this library's OWN
  /// descriptor links back to the listing hub (`memberOf`). That reciprocal
  /// link is the member-side consent anyone can verify — it backs the
  /// "Confirmed by member" badge (design 2026-10-18).
  final bool confirmedByMember;

  /// Last descriptor-fetch outcome.
  final FetchStatus fetchStatus;

  /// Epoch millis of the last successful fetch; null when never.
  final int? fetchedAt;

  /// Epoch millis when the row was created on this device.
  final int createdAt;

  /// Display order among the user's own rows (old bookmark order preserved).
  final int sortOrder;

  /// The URL of this library's published descriptor: `<siteUrl>library.json`
  /// (siteUrl always ends with `/`; `Uri.resolve` keeps the path prefix).
  String get descriptorUrl =>
      Uri.parse(siteUrl).resolve('library.json').toString();

  /// Returns a copy with the given fields replaced.
  ///
  /// Because Dart has no way to pass "explicitly null" through `??`, the
  /// nullable fields get deliberate `clear*` flags: a caller that computes a
  /// row WITHOUT a location it used to have (a library turned sharing off)
  /// passes `clearLocation: true`. The repository's wholesale write paths
  /// (`applyRefresh`) then persist the nulls.
  NetworkLibrary copyWith({
    int? id,
    String? siteUrl,
    String? name,
    String? fingerprint,
    GeoPoint? location,
    LocationPrecision? precision,
    NetworkSource? source,
    bool? isMember,
    bool? memberVerified,
    String? listedByHubUrl,
    MembershipState? membership,
    bool? confirmedByMember,
    FetchStatus? fetchStatus,
    int? fetchedAt,
    int? createdAt,
    int? sortOrder,
    bool clearFingerprint = false,
    bool clearLocation = false,
    bool clearListedByHubUrl = false,
    bool clearFetchedAt = false,
  }) => NetworkLibrary(
    id: id ?? this.id,
    siteUrl: siteUrl ?? this.siteUrl,
    name: name ?? this.name,
    fingerprint: clearFingerprint ? null : (fingerprint ?? this.fingerprint),
    // Location and precision are one unit: clearing drops both (a pin
    // without a declared precision must never exist — same rule as the
    // descriptor codec and the JSON parser).
    location: clearLocation ? null : (location ?? this.location),
    precision: clearLocation ? null : (precision ?? this.precision),
    source: source ?? this.source,
    isMember: isMember ?? this.isMember,
    memberVerified: memberVerified ?? this.memberVerified,
    listedByHubUrl: clearListedByHubUrl
        ? null
        : (listedByHubUrl ?? this.listedByHubUrl),
    membership: membership ?? this.membership,
    confirmedByMember: confirmedByMember ?? this.confirmedByMember,
    fetchStatus: fetchStatus ?? this.fetchStatus,
    fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
    createdAt: createdAt ?? this.createdAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  /// JSON map for the `network.json` backup entry (§3.4). Optional fields are
  /// omitted when null so the archive stays small and honest.
  Map<String, dynamic> toJson() => {
    'id': id,
    'siteUrl': siteUrl,
    'name': name,
    if (fingerprint != null) 'fingerprint': fingerprint,
    if (location != null)
      'location': {'lat': location!.lat, 'lng': location!.lng},
    if (precision != null) 'precision': precision!.name,
    'source': source.name,
    'isMember': isMember,
    'memberVerified': memberVerified,
    if (listedByHubUrl != null) 'listedByHubUrl': listedByHubUrl,
    'membership': membership.name,
    'confirmedByMember': confirmedByMember,
    'fetchStatus': fetchStatus.name,
    if (fetchedAt != null) 'fetchedAt': fetchedAt,
    'createdAt': createdAt,
    'sortOrder': sortOrder,
  };

  /// Parses one row from `network.json` (a HOSTILE archive entry, §6),
  /// re-validating every field. Returns null when the row must be dropped:
  /// a missing/invalid `siteUrl` (the identity) or a malformed
  /// `fingerprint`. Softer fields degrade instead of dropping: an invalid
  /// name becomes '', an invalid location pair is dropped (no pin), unknown
  /// enum tokens fall back to their safest default.
  static NetworkLibrary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;

    final siteUrl = BookmarkUrl.normalize(_asString(json['siteUrl']));
    if (siteUrl == null) return null;

    final rawFingerprint = json['fingerprint'];
    String? fingerprint;
    if (rawFingerprint != null) {
      if (rawFingerprint is! String) return null;
      if (!LibraryFingerprint.isValid(rawFingerprint)) return null;
      fingerprint = rawFingerprint;
    }

    // Location: both coordinates and a valid precision, or nothing.
    GeoPoint? location;
    LocationPrecision? precision;
    final rawLocation = json['location'];
    if (rawLocation is Map<String, dynamic>) {
      final lat = rawLocation['lat'];
      final lng = rawLocation['lng'];
      if (lat is num && lng is num) {
        location = GeoPoint.tryCreate(lat.toDouble(), lng.toDouble());
      }
    }
    if (location != null) {
      precision = _parseEnum(
        LocationPrecision.values,
        _asString(json['precision']),
      );
      if (precision == null) location = null; // no label ⇒ no pin (privacy)
    }

    final listedByHubUrl = BookmarkUrl.normalize(
      _asString(json['listedByHubUrl']),
    );

    return NetworkLibrary(
      id: json['id'] is int && (json['id'] as int) >= 0 ? json['id'] as int : 0,
      siteUrl: siteUrl,
      name: NetworkName.normalizeOrNull(_asString(json['name'])) ?? '',
      fingerprint: fingerprint,
      location: location,
      precision: precision,
      source:
          _parseEnum(NetworkSource.values, _asString(json['source'])) ??
          NetworkSource.bookmark,
      isMember: json['isMember'] == true,
      memberVerified: json['memberVerified'] == true,
      listedByHubUrl: listedByHubUrl,
      membership:
          _parseEnum(MembershipState.values, _asString(json['membership'])) ??
          MembershipState.none,
      // Absent in pre-v4 archives ⇒ false (additive, §3.4).
      confirmedByMember: json['confirmedByMember'] == true,
      fetchStatus:
          _parseEnum(FetchStatus.values, _asString(json['fetchStatus'])) ??
          FetchStatus.never,
      fetchedAt: json['fetchedAt'] is int ? json['fetchedAt'] as int? : null,
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : 0,
      sortOrder: json['sortOrder'] is int ? json['sortOrder'] as int : 0,
    );
  }

  static String? _asString(Object? v) => v is String ? v : null;

  /// Enum by stored name; unknown tokens → null (callers pick the safe
  /// default — a future build's new token must never crash an older restore).
  static T? _parseEnum<T extends Enum>(List<T> values, String? token) {
    if (token == null) return null;
    for (final v in values) {
      if (v.name == token) return v;
    }
    return null;
  }

  /// Field-by-field equality WITHOUT overriding `==`/`hashCode`: the repo's
  /// lint bar flags value equality on classes the analyzer cannot prove
  /// immutable (no `@immutable` in the pure domain — the annotation package
  /// is not on the domain allow-list). Same pattern as `GeoPoint.sameAs`.
  bool sameAs(NetworkLibrary other) =>
      other.id == id &&
      other.siteUrl == siteUrl &&
      other.name == name &&
      other.fingerprint == fingerprint &&
      ((other.location == null && location == null) ||
          (other.location != null &&
              location != null &&
              other.location!.sameAs(location!))) &&
      other.precision == precision &&
      other.source == source &&
      other.isMember == isMember &&
      other.memberVerified == memberVerified &&
      other.listedByHubUrl == listedByHubUrl &&
      other.membership == membership &&
      other.confirmedByMember == confirmedByMember &&
      other.fetchStatus == fetchStatus &&
      other.fetchedAt == fetchedAt &&
      other.createdAt == createdAt &&
      other.sortOrder == sortOrder;

  @override
  String toString() =>
      'NetworkLibrary(${name.isEmpty ? siteUrl : name}, '
      'fp: ${fingerprint == null ? 'none' : 'set'}, '
      'source: ${source.name}, member: $isMember)';
}
