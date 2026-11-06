/// Restore-from-published-site bindings (one direction: restore -> siblings).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/src/cloudflare_publish_providers.dart';
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/import_export_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/network_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/publish_providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/restore/published_cover_restorer.dart';
import 'package:pitaka/features/publish/application/restore/recover_published_identity.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_use_case.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/infrastructure/prefs_restore_identity_journal_store.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_providers.g.dart';

/// Non-secret pending-identity journal.
@riverpod
Future<RestoreIdentityJournalStore> restoreIdentityJournalStore(
  RestoreIdentityJournalStoreRef ref,
) async => PrefsRestoreIdentityJournalStore(
  await ref.watch(sharedPreferencesProvider.future),
);

/// Identity-only recovery over the single settings writer.
@riverpod
Future<RecoverPublishedIdentity> recoverPublishedIdentity(
  RecoverPublishedIdentityRef ref,
) async => RecoverPublishedIdentity(
  journal: await ref.watch(restoreIdentityJournalStoreProvider.future),
  resolveTarget: await ref.watch(activePublishTargetResolverProvider.future),
  items: await ref.watch(catalogueItemRepositoryProvider.future),
  periodicals: await ref.watch(periodicalRepositoryProvider.future),
  writeFingerprint: ref
      .read(settingsControllerProvider.notifier)
      .setPublishedFingerprint,
);

/// One startup attempt; a target mismatch stays pending until Restore retries.
@Riverpod(keepAlive: true)
Future<Either<Failure, PublishedIdentityRecoveryOutcome>>
publishedIdentityStartupRecovery(
  PublishedIdentityStartupRecoveryRef ref,
) async {
  final recover = await ref.watch(recoverPublishedIdentityProvider.future);
  return ref.read(publishOperationQueueProvider).enqueue(recover.call);
}

/// Site-bound restore use case and its bounded network ports.
@riverpod
Future<RestoreFromPublishedSiteUseCase> restoreFromPublishedSiteUseCase(
  RestoreFromPublishedSiteUseCaseRef ref,
  String siteUrl,
) async {
  final clock = ref.watch(clockProvider);
  return RestoreFromPublishedSiteUseCase(
    items: await ref.watch(catalogueItemRepositoryProvider.future),
    periodicals: await ref.watch(periodicalRepositoryProvider.future),
    importer: await ref.watch(importLibraryUseCaseProvider.future),
    coverFiles: await ref.watch(bundleCoverFilesProvider.future),
    coordinator: ref.watch(coverFileCoordinatorProvider),
    fetchCatalogue: ref.watch(publishedCatalogueFetcherProvider(siteUrl)),
    siteReader: ref.watch(publishedSiteReadVerifierProvider),
    coverRestorer: PublishedCoverRestorer(
      fetch: ref.watch(publishedCoverDownloadFetcherProvider(siteUrl)),
      clock: clock,
    ),
    journal: await ref.watch(restoreIdentityJournalStoreProvider.future),
    recoverIdentity: await ref.watch(recoverPublishedIdentityProvider.future),
    clock: clock,
  );
}
