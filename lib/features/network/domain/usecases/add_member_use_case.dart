/// Hub "Add member" by in-person card scan (network domain use case;
/// libNetwork.md §5.7, D2/D13).
///
/// The ONLY way a hub adopts a member: scanning that library's card QR in
/// person. The scan is the trust anchor — the URL alone never makes a row a
/// member. Steps:
///  1. normalise the card's siteUrl and look the row up (the URL is the
///     identity, D13);
///  2. no row ⇒ insert one (`source: card`, `isMember`, unverified);
///     existing row ⇒ flip `isMember`; a fingerprint CONTRADICTION between
///     card and saved row is a typed failure — never overwrite an identity
///     (fail closed). The card's fingerprint already saved under a
///     DIFFERENT address is refused up front too, with a plain sentence:
///     the table's UNIQUE(fingerprint) would otherwise refuse the write as a
///     generic "storage failed" that retrying can never fix (review M5);
///  3. one immediate bounded descriptor fetch to cross-check the published
///     fingerprint against the scanned one. Success sets `memberVerified`;
///     any refusal leaves it false with a visible "unverified" badge — a
///     missing network is NEVER an error here (the member was added in
///     person; the fetch is a bonus).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';

/// Adds (or upgrades) a member row from a scanned [LibraryCard].
final class AddMemberUseCase {
  /// Creates the use case over its ports. [clock] is injectable for tests.
  AddMemberUseCase({
    required NetworkRepository repository,
    required DescriptorFetcher fetchDescriptor,
    int Function()? clock,
  }) : _repository = repository,
       _fetchDescriptor = fetchDescriptor,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NetworkRepository _repository;
  final DescriptorFetcher _fetchDescriptor;
  final int Function() _clock;

  /// The message shown when the scanned card's fingerprint contradicts the
  /// row already saved for that address (§5.7 — exact copy, wire-stable).
  static const String identityMismatchMessage =
      "This card's identity does not match the saved library at this address.";

  /// The message shown when the card's fingerprint is already saved under
  /// another address (the same library at an old or alternative URL).
  static const String identityAlreadySavedMessage =
      "This card's identity is already saved under a different address. "
      'If that library moved, remove the old entry first.';

  /// Runs the add. Right carries the saved row (verified or not); Left is
  /// only ever an identity contradiction or a storage failure.
  Future<Either<Failure, NetworkLibrary>> call(LibraryCard card) async {
    final rows = await _repository.loadAll();
    NetworkLibrary? existing;
    var maxSort = 0;
    for (final row in rows) {
      if (row.siteUrl == card.siteUrl) {
        existing = row;
      } else if (row.fingerprint == card.fingerprint) {
        // One identity, one row (UNIQUE(fingerprint)): say so in words
        // BEFORE any write or fetch instead of surfacing the constraint as
        // an opaque storage error.
        return const Left(ValidationFailure(identityAlreadySavedMessage));
      }
      if (row.sortOrder > maxSort) maxSort = row.sortOrder;
    }

    final NetworkLibrary target;
    if (existing == null) {
      target = NetworkLibrary(
        siteUrl: card.siteUrl,
        name: card.name,
        fingerprint: card.fingerprint,
        source: NetworkSource.card,
        isMember: true,
        createdAt: _clock(),
        sortOrder: maxSort + 1, // append after the user's existing rows
      );
    } else {
      // fingerprint: null ⇒ set; equal ⇒ keep; different ⇒ refuse (§5.7).
      if (existing.fingerprint != null &&
          existing.fingerprint != card.fingerprint) {
        return const Left(ValidationFailure(identityMismatchMessage));
      }
      target = existing.copyWith(
        fingerprint: card.fingerprint,
        isMember: true,
        // A bookmark row may not have had a name yet — the card supplies one.
        name: existing.name.isEmpty ? card.name : existing.name,
      );
    }

    final saved = await _repository.upsertBySiteUrl(target);
    final row = saved.toNullable();
    if (row == null) return saved;

    // The verification fetch: bounded (allow-list + 15 s + 64 KiB inside the
    // injected DescriptorFetcher) and strictly best-effort.
    final fetched = await _fetchDescriptor(row.descriptorUrl);
    switch (fetched) {
      case DescriptorFetched(:final descriptor):
        if (descriptor.fingerprint == row.fingerprint) {
          // The published identity agrees with the scanned card.
          return _repository.upsertBySiteUrl(
            row.copyWith(
              memberVerified: true,
              fetchStatus: FetchStatus.ok,
              fetchedAt: _clock(),
            ),
          );
        }
        // The site publishes a DIFFERENT fingerprint than the card showed in
        // person: do not merge, do not verify — flag it visibly (D12 shape)
        // and let the user decide. The member row itself stays (it was added
        // in person; failing closed here means "warn", not "delete").
        return _repository.upsertBySiteUrl(
          row.copyWith(fetchStatus: FetchStatus.identityConflict),
        );
      case DescriptorRefused():
        // Offline, no descriptor, hostile host — all the same outcome: the
        // member stays unverified with a badge. Never an error (§5.7).
        return right(row);
    }
  }
}
