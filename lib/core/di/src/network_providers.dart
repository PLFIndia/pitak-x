/// Network-feature DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: the one-time legacy-bookmarks migration, the Drift-backed
/// row repository, the bounded descriptor fetcher (the ONLY thing that reads
/// other libraries' `library.json`), and the use cases built on those ports.
///
/// Cross-feature note: this module imports the platform + database base
/// modules only. The publish controller reads `networkRepositoryProvider`
/// for its `members`/`memberOf` lists — publish imports THIS module, one
/// direction.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/confirm_membership_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/migrate_legacy_bookmarks_use_case.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';
import 'package:pitaka/features/network/infrastructure/bounded_descriptor_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/drift_network_repository.dart';
import 'package:pitaka/features/network/infrastructure/legacy_bookmarks_reader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_providers.g.dart';

/// The one-time legacy bookmarks migration (D8/ADR 0012): moves the old
/// `library_bookmarks` prefs list into the network table, then deletes the
/// key. Idempotent — after the first success it reads nothing and does
/// nothing, so awaiting it on every repository hand-out is cheap.
///
/// Fail closed: a migration that cannot complete (storage failure) throws,
/// which errors this provider and everything downstream — the network screen
/// shows its safe error state instead of silently presenting a table that is
/// missing the user's old bookmarks.
@riverpod
Future<Unit> migrateLegacyBookmarks(MigrateLegacyBookmarksRef ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  final reader = LegacyBookmarksReader(prefs);
  final useCase = MigrateLegacyBookmarksUseCase(
    // A private repository instance on purpose: the public
    // networkRepositoryProvider AWAITS this migration, so the migration
    // cannot depend on it (that would be a provider cycle).
    repository: DriftNetworkRepository(db),
    readLegacy: reader.read,
    clearLegacy: reader.clear,
    clock: ref.watch(clockProvider),
  );
  final migrated = await useCase();
  if (migrated.isLeft()) {
    // The Failure itself is data for the caller's Either chain; a provider
    // signals failure by throwing (only Error/Exception are throwable per
    // lint), so wrap — the detail stays out of any UI (§6).
    throw StateError('legacy bookmarks migration failed');
  }
  return unit;
}

/// The network-row repository (Drift, inside the active data generation —
/// rows live with the catalogue so a restore/generation switch takes them
/// along). Awaits the legacy migration FIRST (§5.11), so no screen can ever
/// read the table before the old bookmarks are in it.
@riverpod
Future<NetworkRepository> networkRepository(NetworkRepositoryRef ref) async {
  await ref.watch(migrateLegacyBookmarksProvider.future);
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftNetworkRepository(db);
}

/// The bounded descriptor fetcher as the domain [DescriptorFetcher] port:
/// allow-listed, 15 s abortable deadline, 64 KiB streamed cap, per-hop
/// redirect re-validation, §3.1 parse rules. Shares the app HTTP client.
@riverpod
DescriptorFetcher descriptorFetcher(DescriptorFetcherRef ref) =>
    // The port is a function type — hand out the fetch method, not the class.
    BoundedDescriptorFetcher(client: ref.watch(httpClientProvider)).fetch;

/// Hub "Add member" use case (§5.7).
@riverpod
Future<AddMemberUseCase> addMemberUseCase(AddMemberUseCaseRef ref) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return AddMemberUseCase(
    repository: repo,
    fetchDescriptor: ref.watch(descriptorFetcherProvider),
    clock: ref.watch(clockProvider),
  );
}

/// The Refresh algorithm (§5.6), run by `NetworkRefreshController`.
@riverpod
Future<RefreshNetworkUseCase> refreshNetworkUseCase(
  RefreshNetworkUseCaseRef ref,
) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return RefreshNetworkUseCase(
    repository: repo,
    fetchDescriptor: ref.watch(descriptorFetcherProvider),
    clock: ref.watch(clockProvider),
  );
}

/// Membership confirmation (§5.6 step 4), run by `NetworkController`.
@riverpod
Future<ConfirmMembershipUseCase> confirmMembershipUseCase(
  ConfirmMembershipUseCaseRef ref,
) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return ConfirmMembershipUseCase(repository: repo);
}
