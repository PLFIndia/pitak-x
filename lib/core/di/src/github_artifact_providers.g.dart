// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'github_artifact_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$gitHubArtifactStoresHash() =>
    r'd2e748c4f74f745c57d38444ee29891436872aac';

/// Fresh operation-scoped GitHub artifact spools (never shared between runs).
///
/// The spool root does NO file work here. Its sweep and run folder happen on
/// the first `write`, inside a queued operation (review finding 6).
///
/// Copied from [gitHubArtifactStores].
@ProviderFor(gitHubArtifactStores)
final gitHubArtifactStoresProvider =
    AutoDisposeFutureProvider<GitHubArtifactStoreFactory>.internal(
      gitHubArtifactStores,
      name: r'gitHubArtifactStoresProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$gitHubArtifactStoresHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GitHubArtifactStoresRef =
    AutoDisposeFutureProviderRef<GitHubArtifactStoreFactory>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
