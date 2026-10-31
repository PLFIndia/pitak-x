/// A possible "this library moved" candidate (network domain, pure Dart;
/// Cloudflare plan C10/R17, docs/ARCHITECTURE.md §5.6).
///
/// Why this type exists (beginner note): a library that changes its published
/// address looks, to a reader, like a NEW library whose descriptor happens to
/// publish the SAME identity fingerprint as one already saved. Before
/// Cloudflare plan C10 that situation was surfaced as an untouchable conflict
/// (or refused outright by the add-member flow), which left the user stuck
/// with a dead address and a duplicate row.
///
/// A candidate is the *evidence* for a user decision — never a decision:
///  - the saved row already holds the fingerprint as a FACT (it was fetched or
///    scanned earlier);
///  - a descriptor fetched at a DIFFERENT canonical address published the same
///    fingerprint, and declared its own `siteUrl` to be that address;
///  - the new address came from an explicit user action (added by URL, or
///    scanned from a card in person) — never from a discovered/hostile row.
///
/// Candidates are EPHEMERAL: they are carried in a refresh report or returned
/// by the add-member use case, never persisted. Nothing changes until the user
/// chooses an address, and both the URL and fingerprint uniqueness rules stay
/// in force. There is no automatic following (R17).
library;

import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// One library appears to live at two canonical addresses.
final class LibraryMoveCandidate {
  /// Creates a candidate. [savedSiteUrl] and [fetchedSiteUrl] must be
  /// different canonical addresses (`BookmarkUrl.normalize` results) — the
  /// detector never constructs one for "the same address twice".
  const LibraryMoveCandidate({
    required this.savedRowId,
    required this.savedSiteUrl,
    required this.savedName,
    required this.fetchedSiteUrl,
    required this.fetchedName,
    required this.fingerprint,
    this.fetchedLocation,
    this.fetchedPrecision,
    this.fetchedAt,
    this.fetchedSource,
    this.hasFetchedFacts = true,
  });

  /// Id of the saved row that already held [fingerprint] (the canonical row).
  final int savedRowId;

  /// The address that row is stored at today.
  final String savedSiteUrl;

  /// The saved row's display name ('' when it never learned one).
  final String savedName;

  /// The other canonical address that now publishes the same fingerprint.
  final String fetchedSiteUrl;

  /// The name the descriptor at [fetchedSiteUrl] published.
  final String fetchedName;

  /// The identity both addresses publish (64 lower-case hex).
  final String fingerprint;

  /// Opted-in location published at [fetchedSiteUrl], or null.
  final GeoPoint? fetchedLocation;

  /// Precision of [fetchedLocation]; null exactly when it is null.
  final LocationPrecision? fetchedPrecision;

  /// When the descriptor at [fetchedSiteUrl] was read (epoch millis), or null
  /// for a card scan (nothing was fetched at decision time).
  final int? fetchedAt;

  /// Where the new address came from — a bookmark/URL add or an in-person
  /// card scan. Used only for honest UI copy.
  final NetworkSource? fetchedSource;

  /// True when the fields above came from a descriptor FETCHED at the new
  /// address (a refresh candidate). False for an in-person CARD scan, which
  /// proves the address and the identity but says nothing about the library's
  /// name, pin or fetch status — so an accepted move must not clear them.
  final bool hasFetchedFacts;

  /// True when this describes two DIFFERENT addresses (always true for a
  /// candidate built by the detectors; exposed for defensive callers).
  bool get isDistinct => savedSiteUrl != fetchedSiteUrl;

  /// Field equality without overriding `==`/`hashCode` (same pattern as
  /// `NetworkLibrary.sameAs` — the pure domain cannot be proven immutable by
  /// the analyzer, and the repo's lint bar forbids value equality there).
  bool sameAs(LibraryMoveCandidate other) =>
      other.savedRowId == savedRowId &&
      other.savedSiteUrl == savedSiteUrl &&
      other.savedName == savedName &&
      other.fetchedSiteUrl == fetchedSiteUrl &&
      other.fetchedName == fetchedName &&
      other.fingerprint == fingerprint &&
      ((other.fetchedLocation == null && fetchedLocation == null) ||
          (other.fetchedLocation != null &&
              fetchedLocation != null &&
              other.fetchedLocation!.sameAs(fetchedLocation!))) &&
      other.fetchedPrecision == fetchedPrecision &&
      other.fetchedAt == fetchedAt &&
      other.fetchedSource == fetchedSource &&
      other.hasFetchedFacts == hasFetchedFacts;

  /// Never prints the fingerprint's value (it is public, but a log line is
  /// still an unnecessary identity trail — AGENTS §6.2 posture).
  @override
  String toString() =>
      'LibraryMoveCandidate($savedSiteUrl → $fetchedSiteUrl, '
      'fp: set)';
}

/// Which address the user chose to keep when accepting a candidate (D.5).
enum LibraryMoveChoice {
  /// Keep the address that was already saved (drop the new row).
  keepSavedAddress,

  /// Move the canonical row to the newly discovered/scanned address.
  useNewAddress,
}
