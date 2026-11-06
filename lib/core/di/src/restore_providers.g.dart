// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restore_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$restoreIdentityJournalStoreHash() =>
    r'57069f17fd21d753f865525b46e85f7bd629d809';

/// Non-secret pending-identity journal.
///
/// Copied from [restoreIdentityJournalStore].
@ProviderFor(restoreIdentityJournalStore)
final restoreIdentityJournalStoreProvider =
    AutoDisposeFutureProvider<RestoreIdentityJournalStore>.internal(
      restoreIdentityJournalStore,
      name: r'restoreIdentityJournalStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$restoreIdentityJournalStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RestoreIdentityJournalStoreRef =
    AutoDisposeFutureProviderRef<RestoreIdentityJournalStore>;
String _$pendingRestoreIdentityHash() =>
    r'7a6a1e944a6338bd1ce9eb2f9db3cfa7fee41a15';

/// The durable pending handoff, watched by the connection UI after restarts.
///
/// Copied from [pendingRestoreIdentity].
@ProviderFor(pendingRestoreIdentity)
final pendingRestoreIdentityProvider =
    AutoDisposeFutureProvider<RestoreIdentityJournal?>.internal(
      pendingRestoreIdentity,
      name: r'pendingRestoreIdentityProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pendingRestoreIdentityHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PendingRestoreIdentityRef =
    AutoDisposeFutureProviderRef<RestoreIdentityJournal?>;
String _$preRestorePublishGuardHash() =>
    r'a9ec3f48e01d1747a8fb5c44652bd774def07303';

/// Shared pre-write recovery guard for catalogue, events and availability.
///
/// Copied from [preRestorePublishGuard].
@ProviderFor(preRestorePublishGuard)
final preRestorePublishGuardProvider =
    AutoDisposeFutureProvider<PreRestorePublishGuard>.internal(
      preRestorePublishGuard,
      name: r'preRestorePublishGuardProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$preRestorePublishGuardHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PreRestorePublishGuardRef =
    AutoDisposeFutureProviderRef<PreRestorePublishGuard>;
String _$recoverPublishedIdentityHash() =>
    r'4423e00b9f8e143791187e739ac2af292eb5f227';

/// Identity-only recovery over the single settings writer.
///
/// Copied from [recoverPublishedIdentity].
@ProviderFor(recoverPublishedIdentity)
final recoverPublishedIdentityProvider =
    AutoDisposeFutureProvider<RecoverPublishedIdentity>.internal(
      recoverPublishedIdentity,
      name: r'recoverPublishedIdentityProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$recoverPublishedIdentityHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RecoverPublishedIdentityRef =
    AutoDisposeFutureProviderRef<RecoverPublishedIdentity>;
String _$publishedIdentityStartupRecoveryHash() =>
    r'af6b6bca4e4840821d312e056de616166ad3cb02';

/// One startup attempt; a target mismatch stays pending until Restore retries.
///
/// Copied from [publishedIdentityStartupRecovery].
@ProviderFor(publishedIdentityStartupRecovery)
final publishedIdentityStartupRecoveryProvider =
    FutureProvider<Either<Failure, PublishedIdentityRecoveryOutcome>>.internal(
      publishedIdentityStartupRecovery,
      name: r'publishedIdentityStartupRecoveryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishedIdentityStartupRecoveryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedIdentityStartupRecoveryRef =
    FutureProviderRef<Either<Failure, PublishedIdentityRecoveryOutcome>>;
String _$restoreFromPublishedSiteUseCaseHash() =>
    r'7f471cfb52eb615043c8ba24357d4c683659f85c';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Site-bound restore use case and its bounded network ports.
///
/// Copied from [restoreFromPublishedSiteUseCase].
@ProviderFor(restoreFromPublishedSiteUseCase)
const restoreFromPublishedSiteUseCaseProvider =
    RestoreFromPublishedSiteUseCaseFamily();

/// Site-bound restore use case and its bounded network ports.
///
/// Copied from [restoreFromPublishedSiteUseCase].
class RestoreFromPublishedSiteUseCaseFamily
    extends Family<AsyncValue<RestoreFromPublishedSiteUseCase>> {
  /// Site-bound restore use case and its bounded network ports.
  ///
  /// Copied from [restoreFromPublishedSiteUseCase].
  const RestoreFromPublishedSiteUseCaseFamily();

  /// Site-bound restore use case and its bounded network ports.
  ///
  /// Copied from [restoreFromPublishedSiteUseCase].
  RestoreFromPublishedSiteUseCaseProvider call(String siteUrl) {
    return RestoreFromPublishedSiteUseCaseProvider(siteUrl);
  }

  @override
  RestoreFromPublishedSiteUseCaseProvider getProviderOverride(
    covariant RestoreFromPublishedSiteUseCaseProvider provider,
  ) {
    return call(provider.siteUrl);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'restoreFromPublishedSiteUseCaseProvider';
}

/// Site-bound restore use case and its bounded network ports.
///
/// Copied from [restoreFromPublishedSiteUseCase].
class RestoreFromPublishedSiteUseCaseProvider
    extends AutoDisposeFutureProvider<RestoreFromPublishedSiteUseCase> {
  /// Site-bound restore use case and its bounded network ports.
  ///
  /// Copied from [restoreFromPublishedSiteUseCase].
  RestoreFromPublishedSiteUseCaseProvider(String siteUrl)
    : this._internal(
        (ref) => restoreFromPublishedSiteUseCase(
          ref as RestoreFromPublishedSiteUseCaseRef,
          siteUrl,
        ),
        from: restoreFromPublishedSiteUseCaseProvider,
        name: r'restoreFromPublishedSiteUseCaseProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$restoreFromPublishedSiteUseCaseHash,
        dependencies: RestoreFromPublishedSiteUseCaseFamily._dependencies,
        allTransitiveDependencies:
            RestoreFromPublishedSiteUseCaseFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  RestoreFromPublishedSiteUseCaseProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.siteUrl,
  }) : super.internal();

  final String siteUrl;

  @override
  Override overrideWith(
    FutureOr<RestoreFromPublishedSiteUseCase> Function(
      RestoreFromPublishedSiteUseCaseRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: RestoreFromPublishedSiteUseCaseProvider._internal(
        (ref) => create(ref as RestoreFromPublishedSiteUseCaseRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        siteUrl: siteUrl,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<RestoreFromPublishedSiteUseCase>
  createElement() {
    return _RestoreFromPublishedSiteUseCaseProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RestoreFromPublishedSiteUseCaseProvider &&
        other.siteUrl == siteUrl;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, siteUrl.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin RestoreFromPublishedSiteUseCaseRef
    on AutoDisposeFutureProviderRef<RestoreFromPublishedSiteUseCase> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _RestoreFromPublishedSiteUseCaseProviderElement
    extends AutoDisposeFutureProviderElement<RestoreFromPublishedSiteUseCase>
    with RestoreFromPublishedSiteUseCaseRef {
  _RestoreFromPublishedSiteUseCaseProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as RestoreFromPublishedSiteUseCaseProvider).siteUrl;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
