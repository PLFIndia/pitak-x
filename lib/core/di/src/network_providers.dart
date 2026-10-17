/// Network-feature DI bindings (AGENTS.md §4; SOLID-PLAN S3).
///
/// What lives here: the Drift-backed row repository, the bounded descriptor
/// fetcher (the ONLY thing that reads other libraries' `library.json`), and
/// the use cases built on those two ports.
///
/// Cross-feature note: this module imports the platform + database base
/// modules only. The publish controller reads `networkRepositoryProvider`
/// for its `members` list — publish imports THIS module, one direction.
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/features/network/domain/descriptor_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/infrastructure/bounded_descriptor_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/drift_network_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_providers.g.dart';

/// The network-row repository (Drift, inside the active data generation —
/// rows live with the catalogue so a restore/generation switch takes them
/// along).
///
/// S4 wires the one-time legacy-bookmarks migration in front of this (the
/// provider awaits it first; it is idempotent).
@riverpod
Future<NetworkRepository> networkRepository(NetworkRepositoryRef ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftNetworkRepository(db);
}

/// All saved network rows, in display order. Screens watch this and
/// `invalidate` it after a mutation (add member, remove, refresh).
@riverpod
Future<List<NetworkLibrary>> networkRows(NetworkRowsRef ref) async {
  final repo = await ref.watch(networkRepositoryProvider.future);
  return repo.loadAll();
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
