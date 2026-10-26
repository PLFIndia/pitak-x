/// Accepts ONE user-confirmed library move (network domain use case;
/// Cloudflare plan C10/R17, docs/ARCHITECTURE.md §5.6).
///
/// Why a separate use case (beginner note): the reader may hold two rows that
/// publish the same identity fingerprint — the saved address and a
/// newly-added/scanned address. The user is shown both and picks which one to
/// keep (D.5). Only then may anything be written, and it must land as ONE
/// atomic change:
///  - the canonical row keeps its id, position in the list and every
///    consent/membership decision the user already made;
///  - it takes the chosen address and the fresh remote fields the descriptor
///    published (name, opted-in pin, fingerprint, fetch status/time);
///  - the duplicate row is deleted;
///  - if the user kept the saved address, nothing is repointed — the
///    duplicate is simply dropped.
///
/// Decline is not this use case: it performs NO write at all.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1). The transactional
/// delete-plus-repoint lives behind [NetworkRepository.acceptLibraryMove].
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/library_move_candidate.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';

/// Applies one accepted [LibraryMoveCandidate].
final class ReconcileLibraryMoveUseCase {
  /// Creates the use case over its ports. [clock] is injectable for tests.
  ReconcileLibraryMoveUseCase({
    required NetworkRepository repository,
    int Function()? clock,
  }) : _repository = repository,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final NetworkRepository _repository;
  final int Function() _clock;

  /// Writes the decision. The returned row is the stored canonical row with
  /// its final address; Left is only ever a typed failure (the rows changed
  /// underneath the decision, or the storage refused) — never a thrown
  /// exception, and never a partial write.
  Future<Either<Failure, NetworkLibrary>> call({
    required LibraryMoveCandidate candidate,
    required LibraryMoveChoice choice,
  }) async {
    if (!candidate.isDistinct) {
      // Defensive: the detectors never build one, but a hostile/buggy caller
      // must not be able to "merge" a row with itself.
      return const Left(ValidationFailure('Not a library move.'));
    }

    final rows = await _repository.loadAll();
    NetworkLibrary? canonical;
    NetworkLibrary? placeholder;
    for (final row in rows) {
      if (row.id == candidate.savedRowId) canonical = row;
      if (row.siteUrl == candidate.fetchedSiteUrl) placeholder = row;
    }

    if (canonical == null || canonical.siteUrl != candidate.savedSiteUrl) {
      // The row the user saw is gone (removed meanwhile) or already moved.
      return const Left(NotFoundFailure());
    }
    if (canonical.fingerprint != candidate.fingerprint) {
      // The evidence changed since the decision was offered. Fail closed so
      // the UI can re-read and re-offer instead of applying stale facts.
      return const Left(StaleStateFailure('identity evidence changed'));
    }
    if (placeholder != null) {
      if (placeholder.id == canonical.id) {
        return const Left(ValidationFailure('Not a library move.'));
      }
      if (placeholder.fingerprint != null) {
        // A row that already carries its own identity is an identity
        // conflict, not a move — that is the existing, stricter path (D12).
        return const Left(StaleStateFailure('duplicate has its own identity'));
      }
    }

    final useNewAddress = choice == LibraryMoveChoice.useNewAddress;
    // Fresh remote facts are applied ONLY when a descriptor was actually
    // fetched at the new address (a refresh candidate). A card scan proves
    // the address + identity in person but carries no name/pin/fetch status,
    // so treating its nulls as "the library stopped sharing" would silently
    // erase the user's stored data (the same fail-closed rule as the
    // descriptor codec).
    final fetched = candidate.hasFetchedFacts;
    final next = canonical.copyWith(
      siteUrl: useNewAddress ? candidate.fetchedSiteUrl : null,
      // The chosen address decides which facts are authoritative; identity
      // bookkeeping and the user's own decisions are never touched.
      name: candidate.fetchedName.isEmpty ? null : candidate.fetchedName,
      fingerprint: candidate.fingerprint,
      location: fetched ? candidate.fetchedLocation : null,
      precision: fetched ? candidate.fetchedPrecision : null,
      clearLocation: fetched && candidate.fetchedLocation == null,
      fetchStatus: fetched ? FetchStatus.ok : null,
      fetchedAt: fetched ? _clock() : null,
    );

    final applied = await _repository.acceptLibraryMove(
      canonicalBaseline: canonical,
      canonicalNext: next,
      placeholderBaseline: placeholder,
    );
    return applied.map((_) => next);
  }
}
