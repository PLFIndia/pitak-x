// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'published_availability_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$publishedCatalogueWithAvailabilityHash() =>
    r'd31d7409177ba7e2ef5d3e176862dc8e754e9525';

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

/// The loaded catalogue with every item's tag decided by the ONE rule.
///
/// Watches the availability state as a plain value (never its `future`), so
/// a file that is still loading or that failed simply counts as "no file"
/// and the catalogue shows at once with its inline tags. A refresh keeps the
/// previous file until the new answer arrives (`valueOrNull`).
///
/// Copied from [publishedCatalogueWithAvailability].
@ProviderFor(publishedCatalogueWithAvailability)
const publishedCatalogueWithAvailabilityProvider =
    PublishedCatalogueWithAvailabilityFamily();

/// The loaded catalogue with every item's tag decided by the ONE rule.
///
/// Watches the availability state as a plain value (never its `future`), so
/// a file that is still loading or that failed simply counts as "no file"
/// and the catalogue shows at once with its inline tags. A refresh keeps the
/// previous file until the new answer arrives (`valueOrNull`).
///
/// Copied from [publishedCatalogueWithAvailability].
class PublishedCatalogueWithAvailabilityFamily
    extends Family<AsyncValue<PublishedCatalogueWithAvailability>> {
  /// The loaded catalogue with every item's tag decided by the ONE rule.
  ///
  /// Watches the availability state as a plain value (never its `future`), so
  /// a file that is still loading or that failed simply counts as "no file"
  /// and the catalogue shows at once with its inline tags. A refresh keeps the
  /// previous file until the new answer arrives (`valueOrNull`).
  ///
  /// Copied from [publishedCatalogueWithAvailability].
  const PublishedCatalogueWithAvailabilityFamily();

  /// The loaded catalogue with every item's tag decided by the ONE rule.
  ///
  /// Watches the availability state as a plain value (never its `future`), so
  /// a file that is still loading or that failed simply counts as "no file"
  /// and the catalogue shows at once with its inline tags. A refresh keeps the
  /// previous file until the new answer arrives (`valueOrNull`).
  ///
  /// Copied from [publishedCatalogueWithAvailability].
  PublishedCatalogueWithAvailabilityProvider call(String siteUrl) {
    return PublishedCatalogueWithAvailabilityProvider(siteUrl);
  }

  @override
  PublishedCatalogueWithAvailabilityProvider getProviderOverride(
    covariant PublishedCatalogueWithAvailabilityProvider provider,
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
  String? get name => r'publishedCatalogueWithAvailabilityProvider';
}

/// The loaded catalogue with every item's tag decided by the ONE rule.
///
/// Watches the availability state as a plain value (never its `future`), so
/// a file that is still loading or that failed simply counts as "no file"
/// and the catalogue shows at once with its inline tags. A refresh keeps the
/// previous file until the new answer arrives (`valueOrNull`).
///
/// Copied from [publishedCatalogueWithAvailability].
class PublishedCatalogueWithAvailabilityProvider
    extends AutoDisposeFutureProvider<PublishedCatalogueWithAvailability> {
  /// The loaded catalogue with every item's tag decided by the ONE rule.
  ///
  /// Watches the availability state as a plain value (never its `future`), so
  /// a file that is still loading or that failed simply counts as "no file"
  /// and the catalogue shows at once with its inline tags. A refresh keeps the
  /// previous file until the new answer arrives (`valueOrNull`).
  ///
  /// Copied from [publishedCatalogueWithAvailability].
  PublishedCatalogueWithAvailabilityProvider(String siteUrl)
    : this._internal(
        (ref) => publishedCatalogueWithAvailability(
          ref as PublishedCatalogueWithAvailabilityRef,
          siteUrl,
        ),
        from: publishedCatalogueWithAvailabilityProvider,
        name: r'publishedCatalogueWithAvailabilityProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueWithAvailabilityHash,
        dependencies: PublishedCatalogueWithAvailabilityFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueWithAvailabilityFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueWithAvailabilityProvider._internal(
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
    FutureOr<PublishedCatalogueWithAvailability> Function(
      PublishedCatalogueWithAvailabilityRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueWithAvailabilityProvider._internal(
        (ref) => create(ref as PublishedCatalogueWithAvailabilityRef),
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
  AutoDisposeFutureProviderElement<PublishedCatalogueWithAvailability>
  createElement() {
    return _PublishedCatalogueWithAvailabilityProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueWithAvailabilityProvider &&
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
mixin PublishedCatalogueWithAvailabilityRef
    on AutoDisposeFutureProviderRef<PublishedCatalogueWithAvailability> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueWithAvailabilityProviderElement
    extends AutoDisposeFutureProviderElement<PublishedCatalogueWithAvailability>
    with PublishedCatalogueWithAvailabilityRef {
  _PublishedCatalogueWithAvailabilityProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as PublishedCatalogueWithAvailabilityProvider).siteUrl;
}

String _$publishedAvailabilityControllerHash() =>
    r'7473d5638200a615046d554b53e5b44a26283de1';

abstract class _$PublishedAvailabilityController
    extends
        BuildlessAutoDisposeAsyncNotifier<
          PublishedContent<PublishedAvailabilityFile>?
        > {
  late final String siteUrl;

  FutureOr<PublishedContent<PublishedAvailabilityFile>?> build(String siteUrl);
}

/// The availability file state for the library saved at `siteUrl`.
///
/// Copied from [PublishedAvailabilityController].
@ProviderFor(PublishedAvailabilityController)
const publishedAvailabilityControllerProvider =
    PublishedAvailabilityControllerFamily();

/// The availability file state for the library saved at `siteUrl`.
///
/// Copied from [PublishedAvailabilityController].
class PublishedAvailabilityControllerFamily
    extends Family<AsyncValue<PublishedContent<PublishedAvailabilityFile>?>> {
  /// The availability file state for the library saved at `siteUrl`.
  ///
  /// Copied from [PublishedAvailabilityController].
  const PublishedAvailabilityControllerFamily();

  /// The availability file state for the library saved at `siteUrl`.
  ///
  /// Copied from [PublishedAvailabilityController].
  PublishedAvailabilityControllerProvider call(String siteUrl) {
    return PublishedAvailabilityControllerProvider(siteUrl);
  }

  @override
  PublishedAvailabilityControllerProvider getProviderOverride(
    covariant PublishedAvailabilityControllerProvider provider,
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
  String? get name => r'publishedAvailabilityControllerProvider';
}

/// The availability file state for the library saved at `siteUrl`.
///
/// Copied from [PublishedAvailabilityController].
class PublishedAvailabilityControllerProvider
    extends
        AutoDisposeAsyncNotifierProviderImpl<
          PublishedAvailabilityController,
          PublishedContent<PublishedAvailabilityFile>?
        > {
  /// The availability file state for the library saved at `siteUrl`.
  ///
  /// Copied from [PublishedAvailabilityController].
  PublishedAvailabilityControllerProvider(String siteUrl)
    : this._internal(
        () => PublishedAvailabilityController()..siteUrl = siteUrl,
        from: publishedAvailabilityControllerProvider,
        name: r'publishedAvailabilityControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedAvailabilityControllerHash,
        dependencies: PublishedAvailabilityControllerFamily._dependencies,
        allTransitiveDependencies:
            PublishedAvailabilityControllerFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedAvailabilityControllerProvider._internal(
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
  FutureOr<PublishedContent<PublishedAvailabilityFile>?> runNotifierBuild(
    covariant PublishedAvailabilityController notifier,
  ) {
    return notifier.build(siteUrl);
  }

  @override
  Override overrideWith(PublishedAvailabilityController Function() create) {
    return ProviderOverride(
      origin: this,
      override: PublishedAvailabilityControllerProvider._internal(
        () => create()..siteUrl = siteUrl,
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
  AutoDisposeAsyncNotifierProviderElement<
    PublishedAvailabilityController,
    PublishedContent<PublishedAvailabilityFile>?
  >
  createElement() {
    return _PublishedAvailabilityControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedAvailabilityControllerProvider &&
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
mixin PublishedAvailabilityControllerRef
    on
        AutoDisposeAsyncNotifierProviderRef<
          PublishedContent<PublishedAvailabilityFile>?
        > {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedAvailabilityControllerProviderElement
    extends
        AutoDisposeAsyncNotifierProviderElement<
          PublishedAvailabilityController,
          PublishedContent<PublishedAvailabilityFile>?
        >
    with PublishedAvailabilityControllerRef {
  _PublishedAvailabilityControllerProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as PublishedAvailabilityControllerProvider).siteUrl;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
