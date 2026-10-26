// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'published_catalogue_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$publishedCatalogueControllerHash() =>
    r'352b43d933d90b099bbe684dbcfd674e49041ffb';

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

abstract class _$PublishedCatalogueController
    extends BuildlessAutoDisposeAsyncNotifier<PublishedCatalogue> {
  late final String siteUrl;

  FutureOr<PublishedCatalogue> build(String siteUrl);
}

/// The catalogue state for the library saved at `siteUrl`.
///
/// Copied from [PublishedCatalogueController].
@ProviderFor(PublishedCatalogueController)
const publishedCatalogueControllerProvider =
    PublishedCatalogueControllerFamily();

/// The catalogue state for the library saved at `siteUrl`.
///
/// Copied from [PublishedCatalogueController].
class PublishedCatalogueControllerFamily
    extends Family<AsyncValue<PublishedCatalogue>> {
  /// The catalogue state for the library saved at `siteUrl`.
  ///
  /// Copied from [PublishedCatalogueController].
  const PublishedCatalogueControllerFamily();

  /// The catalogue state for the library saved at `siteUrl`.
  ///
  /// Copied from [PublishedCatalogueController].
  PublishedCatalogueControllerProvider call(String siteUrl) {
    return PublishedCatalogueControllerProvider(siteUrl);
  }

  @override
  PublishedCatalogueControllerProvider getProviderOverride(
    covariant PublishedCatalogueControllerProvider provider,
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
  String? get name => r'publishedCatalogueControllerProvider';
}

/// The catalogue state for the library saved at `siteUrl`.
///
/// Copied from [PublishedCatalogueController].
class PublishedCatalogueControllerProvider
    extends
        AutoDisposeAsyncNotifierProviderImpl<
          PublishedCatalogueController,
          PublishedCatalogue
        > {
  /// The catalogue state for the library saved at `siteUrl`.
  ///
  /// Copied from [PublishedCatalogueController].
  PublishedCatalogueControllerProvider(String siteUrl)
    : this._internal(
        () => PublishedCatalogueController()..siteUrl = siteUrl,
        from: publishedCatalogueControllerProvider,
        name: r'publishedCatalogueControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueControllerHash,
        dependencies: PublishedCatalogueControllerFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueControllerFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueControllerProvider._internal(
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
  FutureOr<PublishedCatalogue> runNotifierBuild(
    covariant PublishedCatalogueController notifier,
  ) {
    return notifier.build(siteUrl);
  }

  @override
  Override overrideWith(PublishedCatalogueController Function() create) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueControllerProvider._internal(
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
    PublishedCatalogueController,
    PublishedCatalogue
  >
  createElement() {
    return _PublishedCatalogueControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueControllerProvider &&
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
mixin PublishedCatalogueControllerRef
    on AutoDisposeAsyncNotifierProviderRef<PublishedCatalogue> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueControllerProviderElement
    extends
        AutoDisposeAsyncNotifierProviderElement<
          PublishedCatalogueController,
          PublishedCatalogue
        >
    with PublishedCatalogueControllerRef {
  _PublishedCatalogueControllerProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as PublishedCatalogueControllerProvider).siteUrl;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
