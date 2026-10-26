/// Hub "Add member" by in-person card scan (network domain use case;
/// docs/ARCHITECTURE.md §5.3).
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
///     DIFFERENT address is no longer a dead end (Cloudflare plan C10/R17):
///     the scan returns a [MemberMoveDetected] offer, and NOTHING is written
///     until the user chooses which address to keep. When the card's address
///     is itself already saved, the two-rows case stays a plain refusal
///     (that is an identity conflict, and the refresh flow offers the merge);
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
import 'package:pitaka/features/network/domain/library_move_candidate.dart';
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
  /// another address AND the card's own address is also saved — a genuine
  /// identity conflict, not a clean move offer.
  static const String identityAlreadySavedMessage =
      "This card's identity is already saved under a different address. "
      'If that library moved, remove the old entry first.';

  /// Runs the add. Right carries either the saved row (verified or not) or a
  /// move offer when the same identity is already saved at another address;
  /// Left is only ever an identity contradiction or a storage failure.
  Future<Either<Failure, AddMemberResult>> call(LibraryCard card) async {
    final rows = await _repository.loadAll();
    NetworkLibrary? existing;
    NetworkLibrary? fingerprintOwner;
    var maxSort = 0;
    for (final row in rows) {
      if (row.siteUrl == card.siteUrl) {
        existing = row;
      } else if (row.fingerprint == card.fingerprint) {
        fingerprintOwner = row;
      }
      if (row.sortOrder > maxSort) maxSort = row.sortOrder;
    }

    if (fingerprintOwner != null) {
      // One identity, one row (UNIQUE(fingerprint)).
      if (existing != null) {
        // The card's address is already saved TOO: two rows claim one
        // identity. Not a clean move — say so in words before any write.
        return const Left(ValidationFailure(identityAlreadySavedMessage));
      }
      // C10/R17: the card (shown in person, the trust anchor) names the same
      // fingerprint as a saved row at another address. Offer the choice and
      // write NOTHING now; an accepted choice goes through
      // ReconcileLibraryMoveUseCase.
      return right(
        MemberMoveDetected(
          LibraryMoveCandidate(
            savedRowId: fingerprintOwner.id,
            savedSiteUrl: fingerprintOwner.siteUrl,
            savedName: fingerprintOwner.name,
            fetchedSiteUrl: card.siteUrl,
            fetchedName: card.name,
            fingerprint: card.fingerprint,
            fetchedSource: NetworkSource.card,
            // A card proves the address and identity in person; it says
            // nothing about the library's name, pin or fetch status.
            hasFetchedFacts: false,
          ),
        ),
      );
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
    if (row == null) return saved.map(MemberAdded.new);

    // The verification fetch: bounded (allow-list + 15 s + 64 KiB inside the
    // injected DescriptorFetcher) and strictly best-effort.
    final fetched = await _fetchDescriptor(row.descriptorUrl);
    switch (fetched) {
      case DescriptorFetched(:final descriptor):
        if (descriptor.fingerprint == row.fingerprint) {
          // The published identity agrees with the scanned card.
          final verified = await _repository.upsertBySiteUrl(
            row.copyWith(
              memberVerified: true,
              fetchStatus: FetchStatus.ok,
              fetchedAt: _clock(),
            ),
          );
          return verified.map(MemberAdded.new);
        }
        // The site publishes a DIFFERENT fingerprint than the card showed in
        // person: do not merge, do not verify — flag it visibly (D12 shape)
        // and let the user decide. The member row itself stays (it was added
        // in person; failing closed here means "warn", not "delete").
        final flagged = await _repository.upsertBySiteUrl(
          row.copyWith(fetchStatus: FetchStatus.identityConflict),
        );
        return flagged.map(MemberAdded.new);
      case DescriptorRefused():
        // Offline, no descriptor, hostile host — all the same outcome: the
        // member stays unverified with a badge. Never an error (§5.7).
        return right(MemberAdded(row));
    }
  }
}

/// What one card scan produced.
sealed class AddMemberResult {
  const AddMemberResult();
}

/// The member row was saved (verified or not — the page shows the badge).
final class MemberAdded extends AddMemberResult {
  /// Creates the added result carrying the stored [row].
  const MemberAdded(this.row);

  /// The saved member row.
  final NetworkLibrary row;
}

/// The scanned card publishes an identity that is already saved at ANOTHER
/// address (C10/R17). Nothing was written: the user must choose.
final class MemberMoveDetected extends AddMemberResult {
  /// Creates the offer carrying the evidence.
  const MemberMoveDetected(this.candidate);

  /// The two addresses and the shared fingerprint.
  final LibraryMoveCandidate candidate;
}
