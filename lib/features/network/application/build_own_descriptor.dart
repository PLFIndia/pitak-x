/// Builds THIS library's own `library.json` descriptor at publish time
/// (network application layer; libNetwork.md §5.5).
///
/// A pure function of settings + identity + site URL — no IO, no Riverpod —
/// so every branch (sharing off/approximate/exact, blank name, invalid ID) is
/// unit-testable without a device. `PublishController` calls it and hands the
/// encoded bytes to `PublishLibraryUseCase`, which commits them next to
/// `books.json` in the SAME atomic commit.
///
/// The raw library ID NEVER enters the descriptor: only its fingerprint
/// (D3). `members` (rows added by card scan) and `memberOf` (confirmed hub
/// memberships) stay empty until the network table exists (S3/S4).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Pure builder for the published self-descriptor.
abstract final class BuildOwnDescriptor {
  /// Fallback display name when the library name is blank or fails the
  /// network name rules (§5.5: blank ⇒ "Pitak library").
  static const String fallbackName = 'Pitak library';

  /// Builds the descriptor, or a [Failure] when the inputs cannot produce an
  /// honest one (invalid identity or site URL). Fail closed: a descriptor
  /// without a fingerprint would be unmatchable by every hub, so publishing
  /// is refused rather than degraded.
  static Either<Failure, LibraryDescriptor> build({
    required String libraryId,
    required String libraryName,
    required String siteUrl,
    required LocationSharing sharing,
    required String gps,
    required int updatedAt,
    List<MemberEntry> members = const [],
    List<String> memberOf = const [],
  }) {
    final fingerprint = LibraryFingerprint.of(libraryId);
    if (fingerprint == null) {
      return const Left(ValidationFailure('Library identity unavailable'));
    }
    final normalizedUrl = BookmarkUrl.normalize(siteUrl);
    if (normalizedUrl == null) {
      return const Left(ValidationFailure('Published site URL unavailable'));
    }

    // D7: the sharing switch decides what — if anything — is published.
    // `off` ⇒ no location block at all; `approximate` ⇒ coordinates coarsened
    // to ~1.1 km; `exact` ⇒ as typed. An unparseable/blank gps value simply
    // yields no location (a pin was never promised for free text).
    GeoPoint? location;
    LocationPrecision? precision;
    if (sharing != LocationSharing.off) {
      final parsed = GeoPoint.parse(gps);
      if (parsed != null) {
        location = sharing == LocationSharing.approximate
            ? parsed.coarsen()
            : parsed;
        precision = sharing == LocationSharing.approximate
            ? LocationPrecision.approximate
            : LocationPrecision.exact;
      }
    }

    return Right(
      LibraryDescriptor(
        fingerprint: fingerprint,
        name: NetworkName.normalizeOrNull(libraryName) ?? fallbackName,
        siteUrl: normalizedUrl,
        updatedAt: updatedAt,
        location: location,
        precision: precision,
        members: members,
        memberOf: memberOf,
      ),
    );
  }
}
