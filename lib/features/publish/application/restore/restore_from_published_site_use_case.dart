/// Restores public catalogue data from the user's own active publish target.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/library_descriptor_codec.dart';
import 'package:pitaka/features/network/domain/published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/application/restore/published_catalogue_mapper.dart';
import 'package:pitaka/features/publish/application/restore/published_cover_restorer.dart';
import 'package:pitaka/features/publish/application/restore/published_restore_covers.dart';
import 'package:pitaka/features/publish/application/restore/recover_published_identity.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Coordinates defensive reads, mapping, bounded covers and atomic import.
final class RestoreFromPublishedSiteUseCase {
  /// Creates the use case over injected ports.
  const RestoreFromPublishedSiteUseCase({
    required CatalogueItemRepository items,
    required PeriodicalRepository periodicals,
    required ImportLibraryUseCase importer,
    required BundleCoverFiles coverFiles,
    required CoverFileCoordinator coordinator,
    required PublishedCatalogueFetcher fetchCatalogue,
    required PublishedSiteReadVerifier siteReader,
    required PublishedCoverRestorer coverRestorer,
    required RestoreIdentityJournalStore journal,
    required RecoverPublishedIdentity recoverIdentity,
    required int Function() clock,
  }) : _items = items,
       _periodicals = periodicals,
       _importer = importer,
       _coverFiles = coverFiles,
       _coordinator = coordinator,
       _fetchCatalogue = fetchCatalogue,
       _siteReader = siteReader,
       _coverRestorer = coverRestorer,
       _journal = journal,
       _recoverIdentity = recoverIdentity,
       _clock = clock;

  final CatalogueItemRepository _items;
  final PeriodicalRepository _periodicals;
  final ImportLibraryUseCase _importer;
  final BundleCoverFiles _coverFiles;
  final CoverFileCoordinator _coordinator;
  final PublishedCatalogueFetcher _fetchCatalogue;
  final PublishedSiteReadVerifier _siteReader;
  final PublishedCoverRestorer _coverRestorer;
  final RestoreIdentityJournalStore _journal;
  final RecoverPublishedIdentity _recoverIdentity;
  final int Function() _clock;

  /// Restores [siteUrl], or returns a typed failure/cancelled outcome.
  Future<Either<Failure, RestoreFromPublishedSiteOutcome>> call(
    String siteUrl, {
    bool downloadCovers = true,
    Future<void>? abortTrigger,
    bool Function()? isCancelled,
    RestoreFromPublishedSiteProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const RestoreFromPublishedSiteProgress(
        RestoreFromPublishedSitePhase.reading,
      ),
    );
    // A pending handoff is an explicit user action, never a hidden side
    // effect of Restore. This also keeps the empty-only rule from masking the
    // recovery button after a process restart.
    final earlier = await _journal.load();
    final pendingJournalFailure = earlier.swap().toNullable();
    if (pendingJournalFailure != null) return left(pendingJournalFailure);
    if (earlier.toNullable() != null) {
      return left(
        const ValidationFailure(
          'Finish identity recovery first (Publish to web → Connection → '
          'Finish identity recovery).',
        ),
      );
    }
    final notEmpty = await _nonEmptyMessage();
    if (notEmpty != null) return left(notEmpty);

    var identityMissing = false;
    String? fingerprint;
    final descriptorRead = await _siteReader.readOutcome(
      siteUrl: siteUrl,
      path: 'library.json',
      maxBytes: LibraryDescriptorCodec.maxBodyBytes,
      cacheBuster: 'restore',
    );
    switch (descriptorRead) {
      case PublishedSiteReadAbsent():
        identityMissing = true;
      case PublishedSiteReadUnreadable():
        return left(
          const ValidationFailure(
            'Your published identity could not be read. Check the connection '
            'and try again. Nothing was imported.',
          ),
        );
      case PublishedSiteReadBody(:final bytes):
        final descriptor = LibraryDescriptorCodec.decode(bytes).toNullable();
        if (descriptor == null) {
          return left(
            const ValidationFailure(
              'Your published identity is unreadable or belongs to a newer '
              'version. Nothing was imported.',
            ),
          );
        }
        fingerprint = descriptor.fingerprint;
    }
    if (isCancelled?.call() ?? false) {
      return right(const RestoreFromPublishedSiteCancelled());
    }

    final url = PublishedSiteUrlPolicy.catalogueUrl(siteUrl);
    if (url == null) {
      return left(const ValidationFailure('Published site URL unavailable'));
    }
    final fetched = await _fetchCatalogue(url, abortTrigger: abortTrigger);
    final PublishedCatalogue catalogue;
    switch (fetched) {
      case PublishedFileFetched(:final value):
        catalogue = value;
      case PublishedFileFailed(:final failure):
        return left(failure);
      case PublishedFileMissing() || PublishedFileUnchanged():
        return left(
          const ValidationFailure(
            'The published catalogue could not be read. Nothing was imported.',
          ),
        );
    }
    if (isCancelled?.call() ?? false) {
      return right(const RestoreFromPublishedSiteCancelled());
    }
    // One stamp links the durable journal to exactly the rows this restore
    // commits; recovery must not adopt an identity for unrelated rows.
    final addedDate = _clock();
    final mappedResult = mapPublishedCatalogueForRestore(
      catalogue,
      addedDate: addedDate,
    );
    final mapFailure = mappedResult.swap().toNullable();
    if (mapFailure != null) return left(mapFailure);
    var mapped = mappedResult.toNullable()!;

    final downloaded = await _coverRestorer.download(
      siteUrl,
      mapped,
      enabled: downloadCovers,
      abortTrigger: abortTrigger,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
    if (downloaded.cancelled) {
      return right(const RestoreFromPublishedSiteCancelled());
    }
    mapped = retainPublishedCovers(mapped, downloaded.covers.keys.toSet());
    final coverCount = downloaded.covers.length;
    final skippedCoverCount = mapped.coverSources.length - coverCount;
    final validated = ImportBundle.validate(mapped.payload, downloaded.covers);
    // Validation owns defensive copies now. Release the originals before DB
    // and file work instead of keeping two retained cover sets alive.
    if (downloaded.covers.isNotEmpty) downloaded.covers.clear();
    final bundleFailure = validated.swap().toNullable();
    if (bundleFailure != null) return left(bundleFailure);

    // Durable BEFORE the DB transaction: startup can tell a pre-commit crash
    // (no row with this stamp) from a post-commit one (a matching row).
    final journaled = await _journal.save(
      RestoreIdentityJournal(
        siteUrl: siteUrl,
        addedDate: addedDate,
        fingerprint: fingerprint,
      ),
    );
    final journalFailure = journaled.swap().toNullable();
    if (journalFailure != null) return left(journalFailure);

    onProgress?.call(
      const RestoreFromPublishedSiteProgress(
        RestoreFromPublishedSitePhase.writing,
      ),
    );
    final imported = await _importer.importBundle(
      validated.toNullable()!,
      coverFiles: _coverFiles,
      coordinator: _coordinator,
      requireEmptyCatalogue: true,
    );
    final importFailure = imported.swap().toNullable();
    if (importFailure != null) {
      await _journal.clear();
      return left(importFailure);
    }

    final recovered = await _recoverIdentity.call();
    final identityPending =
        recovered.isLeft() ||
        recovered.toNullable() != PublishedIdentityRecoveryOutcome.recovered;
    return right(
      RestoreFromPublishedSiteSuccess(
        RestoreFromPublishedSiteSummary(
          import: imported.toNullable()!,
          rowsDropped: mapped.droppedRows,
          droppedFields: mapped.droppedFields,
          issuesFiledAsBooks: mapped.issuesFiledAsBooks,
          coversRestored: coverCount,
          coversFailed: downloadCovers
              ? skippedCoverCount - downloaded.skippedByBudget
              : 0,
          coversSkippedByBudget: downloaded.skippedByBudget,
          coversNotDownloaded: downloadCovers ? 0 : skippedCoverCount,
          thirdPartyCoverLinks: mapped.thirdPartyCoverLinks,
          downloadCovers: downloadCovers,
          identityMissing: identityMissing,
          identityPending: identityPending,
        ),
      ),
    );
  }

  Future<Failure?> _nonEmptyMessage() async {
    final items = await _items.getAll();
    final itemsFailure = items.swap().toNullable();
    if (itemsFailure != null) return itemsFailure;
    final titles = await _periodicals.listAll();
    final titlesFailure = titles.swap().toNullable();
    if (titlesFailure != null) return titlesFailure;
    final itemCount = items.toNullable()!.length;
    final titleCount = titles.toNullable()!.length;
    if (itemCount == 0 && titleCount == 0) return null;
    return ValidationFailure(
      'Restore works into an empty catalogue. You have $itemCount items and '
      '$titleCount magazine titles.',
    );
  }
}
