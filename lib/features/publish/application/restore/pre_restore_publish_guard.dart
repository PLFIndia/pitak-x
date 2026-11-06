/// Prevents a fresh install from publishing over its only recovery copy.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/network/domain/published_catalogue_fetcher.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Fail-closed write guard shared by every publish lane.
final class PreRestorePublishGuard {
  /// Creates the guard over local reads and the bounded remote reader.
  const PreRestorePublishGuard({
    required CatalogueItemRepository items,
    required PeriodicalRepository periodicals,
    required RestoreIdentityJournalStore journal,
    required PublishedSiteReadVerifier reader,
    required PublishedCatalogueDecoder decode,
  }) : _items = items,
       _periodicals = periodicals,
       _journal = journal,
       _reader = reader,
       _decode = decode;

  final CatalogueItemRepository _items;
  final PeriodicalRepository _periodicals;
  final RestoreIdentityJournalStore _journal;
  final PublishedSiteReadVerifier _reader;
  final PublishedCatalogueDecoder _decode;

  /// Fixed safe copy shown when publishing could destroy recovery data.
  static const recoveryMessage =
      'This site may hold the only recovery copy of your catalogue. Use '
      'Restore from this site before publishing. Nothing was published.';

  /// Allows a write only when no pending identity or recovery copy is at risk.
  Future<Either<Failure, Unit>> call(PublishTarget target) async {
    final pending = await _journal.load();
    final journalFailure = pending.swap().toNullable();
    if (journalFailure != null) return left(journalFailure);
    if (pending.toNullable() != null) {
      return left(
        const ValidationFailure(
          'Finish restoring your published identity before publishing. Open '
          'Publish to web → Connection → Finish identity recovery. Nothing '
          'was published.',
        ),
      );
    }
    final items = await _items.getAll();
    final itemsFailure = items.swap().toNullable();
    if (itemsFailure != null) {
      return left(
        const PublishReadFailure(PublishSnapshotBuilder.readFailedMessage),
      );
    }
    final titles = await _periodicals.listAll();
    final titlesFailure = titles.swap().toNullable();
    if (titlesFailure != null) {
      return left(
        const PublishReadFailure(PublishSnapshotBuilder.readFailedMessage),
      );
    }
    if (items.toNullable()!.isNotEmpty || titles.toNullable()!.isNotEmpty) {
      return right(unit);
    }

    final remote = await _reader.readOutcome(
      siteUrl: target.siteUrl,
      path: 'books.json',
      maxBytes: publishedCatalogueReadBackMaxBytes,
      cacheBuster: 'pre-restore',
    );
    switch (remote) {
      case PublishedSiteReadAbsent():
        return right(unit);
      case PublishedSiteReadUnreadable():
        return left(const ValidationFailure(recoveryMessage));
      case PublishedSiteReadBody(:final bytes):
        final decoded = await _decode(Uint8List.fromList(bytes));
        final catalogue = decoded.toNullable();
        if (catalogue == null) {
          return left(const ValidationFailure(recoveryMessage));
        }
        final warnings = catalogue.warnings;
        final hasRecoveryData =
            catalogue.items.isNotEmpty ||
            catalogue.periodicals.isNotEmpty ||
            warnings.droppedItems > 0 ||
            warnings.droppedPeriodicals > 0 ||
            warnings.itemsTruncated ||
            warnings.periodicalsTruncated;
        if (hasRecoveryData) {
          return left(const ValidationFailure(recoveryMessage));
        }
        return right(unit);
    }
  }
}
