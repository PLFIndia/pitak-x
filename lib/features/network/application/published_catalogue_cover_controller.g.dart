// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'published_catalogue_cover_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$publishedCatalogueCoverControllerHash() =>
    r'27b853edef89f49928b2505a37d0c195d628cf66';

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

abstract class _$PublishedCatalogueCoverController
    extends BuildlessAutoDisposeNotifier<PublishedCoverSession> {
  late final String siteUrl;

  PublishedCoverSession build(String siteUrl);
}

/// Schedules and caches published covers for one viewer session.
///
/// Copied from [PublishedCatalogueCoverController].
@ProviderFor(PublishedCatalogueCoverController)
const publishedCatalogueCoverControllerProvider =
    PublishedCatalogueCoverControllerFamily();

/// Schedules and caches published covers for one viewer session.
///
/// Copied from [PublishedCatalogueCoverController].
class PublishedCatalogueCoverControllerFamily
    extends Family<PublishedCoverSession> {
  /// Schedules and caches published covers for one viewer session.
  ///
  /// Copied from [PublishedCatalogueCoverController].
  const PublishedCatalogueCoverControllerFamily();

  /// Schedules and caches published covers for one viewer session.
  ///
  /// Copied from [PublishedCatalogueCoverController].
  PublishedCatalogueCoverControllerProvider call(String siteUrl) {
    return PublishedCatalogueCoverControllerProvider(siteUrl);
  }

  @override
  PublishedCatalogueCoverControllerProvider getProviderOverride(
    covariant PublishedCatalogueCoverControllerProvider provider,
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
  String? get name => r'publishedCatalogueCoverControllerProvider';
}

/// Schedules and caches published covers for one viewer session.
///
/// Copied from [PublishedCatalogueCoverController].
class PublishedCatalogueCoverControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          PublishedCatalogueCoverController,
          PublishedCoverSession
        > {
  /// Schedules and caches published covers for one viewer session.
  ///
  /// Copied from [PublishedCatalogueCoverController].
  PublishedCatalogueCoverControllerProvider(String siteUrl)
    : this._internal(
        () => PublishedCatalogueCoverController()..siteUrl = siteUrl,
        from: publishedCatalogueCoverControllerProvider,
        name: r'publishedCatalogueCoverControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueCoverControllerHash,
        dependencies: PublishedCatalogueCoverControllerFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueCoverControllerFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueCoverControllerProvider._internal(
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
  PublishedCoverSession runNotifierBuild(
    covariant PublishedCatalogueCoverController notifier,
  ) {
    return notifier.build(siteUrl);
  }

  @override
  Override overrideWith(PublishedCatalogueCoverController Function() create) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueCoverControllerProvider._internal(
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
  AutoDisposeNotifierProviderElement<
    PublishedCatalogueCoverController,
    PublishedCoverSession
  >
  createElement() {
    return _PublishedCatalogueCoverControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueCoverControllerProvider &&
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
mixin PublishedCatalogueCoverControllerRef
    on AutoDisposeNotifierProviderRef<PublishedCoverSession> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueCoverControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          PublishedCatalogueCoverController,
          PublishedCoverSession
        >
    with PublishedCatalogueCoverControllerRef {
  _PublishedCatalogueCoverControllerProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as PublishedCatalogueCoverControllerProvider).siteUrl;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
