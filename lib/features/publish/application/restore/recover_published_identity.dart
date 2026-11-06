/// Completes or discards a durable restore-identity handoff.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/application/site/active_publish_target.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';

/// Single-writer settings port for the recovered public label.
typedef PublishedFingerprintWriter =
    Future<Either<Failure, Unit>> Function(String? fingerprint);

/// What a recovery attempt found or completed.
enum PublishedIdentityRecoveryOutcome {
  /// No journal exists.
  none,

  /// The fingerprint was saved and the journal cleared.
  recovered,

  /// The same target is not connected, or a write is still outstanding.
  pending,

  /// A pre-commit journal was cleared without adopting an identity.
  discarded,
}

/// Completes identity persistence after an interrupted site restore.
final class RecoverPublishedIdentity {
  /// Creates recovery over the journal, target, repositories and writer.
  const RecoverPublishedIdentity({
    required RestoreIdentityJournalStore journal,
    required ActivePublishTargetResolver resolveTarget,
    required CatalogueItemRepository items,
    required PeriodicalRepository periodicals,
    required PublishedFingerprintWriter writeFingerprint,
  }) : _journal = journal,
       _resolveTarget = resolveTarget,
       _items = items,
       _periodicals = periodicals,
       _writeFingerprint = writeFingerprint;

  final RestoreIdentityJournalStore _journal;
  final ActivePublishTargetResolver _resolveTarget;
  final CatalogueItemRepository _items;
  final PeriodicalRepository _periodicals;
  final PublishedFingerprintWriter _writeFingerprint;

  /// Runs one local recovery attempt; no published file is fetched.
  Future<Either<Failure, PublishedIdentityRecoveryOutcome>> call() async {
    final loaded = await _journal.load();
    final pending = loaded.toNullable();
    if (pending == null) {
      return loaded.map((_) => PublishedIdentityRecoveryOutcome.none);
    }
    final target = await _resolveTarget.call();
    final site = target.toNullable()?.siteUrl;
    if (site == null || site != pending.siteUrl) {
      return right(PublishedIdentityRecoveryOutcome.pending);
    }
    final items = await _items.getAll();
    final itemsFailure = items.swap().toNullable();
    if (itemsFailure != null) return left(itemsFailure);
    final titles = await _periodicals.listAll();
    final titlesFailure = titles.swap().toNullable();
    if (titlesFailure != null) return left(titlesFailure);
    final committed =
        items.toNullable()!.isNotEmpty || titles.toNullable()!.isNotEmpty;
    if (!committed) {
      // The journal is written BEFORE import. Empty tables prove the crash
      // happened before commit (empty site restores are refused), so no
      // identity may be adopted from an import that never happened.
      return (await _journal.clear()).map(
        (_) => PublishedIdentityRecoveryOutcome.discarded,
      );
    }
    final written = await _writeFingerprint(pending.fingerprint);
    final writeFailure = written.swap().toNullable();
    if (writeFailure != null) return left(writeFailure);
    return (await _journal.clear()).map(
      (_) => PublishedIdentityRecoveryOutcome.recovered,
    );
  }
}
