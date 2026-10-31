// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloudflare_publish_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$cloudflarePublishPreflightReaderHash() =>
    r'475e055c5a79e6767698dbd29bcf6dcaeb408305';

/// Read-only ordinary-publish preflight; no route or upload writes.
///
/// Copied from [cloudflarePublishPreflightReader].
@ProviderFor(cloudflarePublishPreflightReader)
final cloudflarePublishPreflightReaderProvider =
    AutoDisposeProvider<CloudflarePublishPreflightReader>.internal(
      cloudflarePublishPreflightReader,
      name: r'cloudflarePublishPreflightReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cloudflarePublishPreflightReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CloudflarePublishPreflightReaderRef =
    AutoDisposeProviderRef<CloudflarePublishPreflightReader>;
String _$cloudflareReplacementPreparationHash() =>
    r'1aeb87101641ceb8e6e26966d73b795af82785a9';

/// Strict complete snapshots and canonical replacement digests.
///
/// Copied from [cloudflareReplacementPreparation].
@ProviderFor(cloudflareReplacementPreparation)
final cloudflareReplacementPreparationProvider =
    AutoDisposeFutureProvider<CloudflareReplacementPreparation>.internal(
      cloudflareReplacementPreparation,
      name: r'cloudflareReplacementPreparationProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cloudflareReplacementPreparationHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CloudflareReplacementPreparationRef =
    AutoDisposeFutureProviderRef<CloudflareReplacementPreparation>;
String _$cloudflarePublicationVerifierHash() =>
    r'c971a8188e48a111771f28a56bf0458e0e7b09cd';

/// Grouped, exact-origin verification of a complete ordinary publication.
///
/// Copied from [cloudflarePublicationVerifier].
@ProviderFor(cloudflarePublicationVerifier)
final cloudflarePublicationVerifierProvider =
    AutoDisposeProvider<CloudflarePublicationVerifier>.internal(
      cloudflarePublicationVerifier,
      name: r'cloudflarePublicationVerifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cloudflarePublicationVerifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CloudflarePublicationVerifierRef =
    AutoDisposeProviderRef<CloudflarePublicationVerifier>;
String _$cloudflareVerifiedStateCommitHash() =>
    r'125998ae798eae92e1dc7e913cba5a1d28946bc9';

/// Ordered live -> journal -> secure-connection commits after read-back.
///
/// Copied from [cloudflareVerifiedStateCommit].
@ProviderFor(cloudflareVerifiedStateCommit)
final cloudflareVerifiedStateCommitProvider =
    AutoDisposeFutureProvider<CloudflareVerifiedStateCommit>.internal(
      cloudflareVerifiedStateCommit,
      name: r'cloudflareVerifiedStateCommitProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cloudflareVerifiedStateCommitHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CloudflareVerifiedStateCommitRef =
    AutoDisposeFutureProviderRef<CloudflareVerifiedStateCommit>;
String _$cloudflareArtifactStoresHash() =>
    r'9584bbe5a233307943cdd990e94321aa4b8452bd';

/// Fresh operation-scoped public-artifact spools (never shared between runs).
///
/// The spool root is built here but does NO file work: the sweep and the run
/// folder happen on the first `spool()` call, which is always inside a queued
/// operation. Building a provider must never touch the filesystem, because the
/// move providers are built outside the queue and could race a publish
/// (fix-plan L5).
///
/// Copied from [cloudflareArtifactStores].
@ProviderFor(cloudflareArtifactStores)
final cloudflareArtifactStoresProvider =
    AutoDisposeFutureProvider<CloudflareArtifactStoreFactory>.internal(
      cloudflareArtifactStores,
      name: r'cloudflareArtifactStoresProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cloudflareArtifactStoresHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CloudflareArtifactStoresRef =
    AutoDisposeFutureProviderRef<CloudflareArtifactStoreFactory>;
String _$publishToCloudflareUseCaseHash() =>
    r'1972ad58831eea4801439e651c585a09dc76eeaa';

/// The ONE Cloudflare ordinary-publish wiring shared by catalogue and events.
///
/// Copied from [publishToCloudflareUseCase].
@ProviderFor(publishToCloudflareUseCase)
final publishToCloudflareUseCaseProvider =
    AutoDisposeFutureProvider<PublishToCloudflareUseCaseFactory>.internal(
      publishToCloudflareUseCase,
      name: r'publishToCloudflareUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishToCloudflareUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishToCloudflareUseCaseRef =
    AutoDisposeFutureProviderRef<PublishToCloudflareUseCaseFactory>;
String _$activePublishTargetResolverHash() =>
    r'af99f1be4a1f0cf65bca38d21c2395181833b756';

/// Active-host target resolution shared by both ordinary publish commands.
///
/// Copied from [activePublishTargetResolver].
@ProviderFor(activePublishTargetResolver)
final activePublishTargetResolverProvider =
    AutoDisposeFutureProvider<ActivePublishTargetResolver>.internal(
      activePublishTargetResolver,
      name: r'activePublishTargetResolverProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activePublishTargetResolverHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ActivePublishTargetResolverRef =
    AutoDisposeFutureProviderRef<ActivePublishTargetResolver>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
