// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$networkRepositoryHash() => r'2cea5a07ccc621dcf9fe088ac0a250d7ab6c722a';

/// The network-row repository (Drift, inside the active data generation —
/// rows live with the catalogue so a restore/generation switch takes them
/// along).
///
/// S4 wires the one-time legacy-bookmarks migration in front of this (the
/// provider awaits it first; it is idempotent).
///
/// Copied from [networkRepository].
@ProviderFor(networkRepository)
final networkRepositoryProvider =
    AutoDisposeFutureProvider<NetworkRepository>.internal(
      networkRepository,
      name: r'networkRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$networkRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NetworkRepositoryRef = AutoDisposeFutureProviderRef<NetworkRepository>;
String _$networkRowsHash() => r'a884f43caaaf9b08ab5796b9414ec4fa5a09dc79';

/// All saved network rows, in display order. Screens watch this and
/// `invalidate` it after a mutation (add member, remove, refresh).
///
/// Copied from [networkRows].
@ProviderFor(networkRows)
final networkRowsProvider =
    AutoDisposeFutureProvider<List<NetworkLibrary>>.internal(
      networkRows,
      name: r'networkRowsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$networkRowsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NetworkRowsRef = AutoDisposeFutureProviderRef<List<NetworkLibrary>>;
String _$descriptorFetcherHash() => r'63bb63bc2b2e585b4d39589242f1007eeaa543a2';

/// The bounded descriptor fetcher as the domain [DescriptorFetcher] port:
/// allow-listed, 15 s abortable deadline, 64 KiB streamed cap, per-hop
/// redirect re-validation, §3.1 parse rules. Shares the app HTTP client.
///
/// Copied from [descriptorFetcher].
@ProviderFor(descriptorFetcher)
final descriptorFetcherProvider =
    AutoDisposeProvider<DescriptorFetcher>.internal(
      descriptorFetcher,
      name: r'descriptorFetcherProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$descriptorFetcherHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DescriptorFetcherRef = AutoDisposeProviderRef<DescriptorFetcher>;
String _$addMemberUseCaseHash() => r'83be6237f974dc356ec0613d556f0cbca1f18f21';

/// Hub "Add member" use case (§5.7).
///
/// Copied from [addMemberUseCase].
@ProviderFor(addMemberUseCase)
final addMemberUseCaseProvider =
    AutoDisposeFutureProvider<AddMemberUseCase>.internal(
      addMemberUseCase,
      name: r'addMemberUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addMemberUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddMemberUseCaseRef = AutoDisposeFutureProviderRef<AddMemberUseCase>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
