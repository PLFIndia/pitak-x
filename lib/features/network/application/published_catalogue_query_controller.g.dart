// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'published_catalogue_query_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$publishedCatalogueViewHash() =>
    r'5d5f14f305c6dbfba3d86cf06a4038c420dcb026';

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

/// The display view: the pure engine applied to the loaded catalogue and the
/// debounced query intent.
///
/// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
/// never on the UI isolate in production. Riverpod attributes each result to
/// the build that asked for it, so a late pass for an older intent cannot
/// overwrite a newer answer; the revision tests pin that behaviour.
///
/// Copied from [publishedCatalogueView].
@ProviderFor(publishedCatalogueView)
const publishedCatalogueViewProvider = PublishedCatalogueViewFamily();

/// The display view: the pure engine applied to the loaded catalogue and the
/// debounced query intent.
///
/// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
/// never on the UI isolate in production. Riverpod attributes each result to
/// the build that asked for it, so a late pass for an older intent cannot
/// overwrite a newer answer; the revision tests pin that behaviour.
///
/// Copied from [publishedCatalogueView].
class PublishedCatalogueViewFamily
    extends Family<AsyncValue<PublishedCatalogueView>> {
  /// The display view: the pure engine applied to the loaded catalogue and the
  /// debounced query intent.
  ///
  /// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
  /// never on the UI isolate in production. Riverpod attributes each result to
  /// the build that asked for it, so a late pass for an older intent cannot
  /// overwrite a newer answer; the revision tests pin that behaviour.
  ///
  /// Copied from [publishedCatalogueView].
  const PublishedCatalogueViewFamily();

  /// The display view: the pure engine applied to the loaded catalogue and the
  /// debounced query intent.
  ///
  /// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
  /// never on the UI isolate in production. Riverpod attributes each result to
  /// the build that asked for it, so a late pass for an older intent cannot
  /// overwrite a newer answer; the revision tests pin that behaviour.
  ///
  /// Copied from [publishedCatalogueView].
  PublishedCatalogueViewProvider call(String siteUrl) {
    return PublishedCatalogueViewProvider(siteUrl);
  }

  @override
  PublishedCatalogueViewProvider getProviderOverride(
    covariant PublishedCatalogueViewProvider provider,
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
  String? get name => r'publishedCatalogueViewProvider';
}

/// The display view: the pure engine applied to the loaded catalogue and the
/// debounced query intent.
///
/// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
/// never on the UI isolate in production. Riverpod attributes each result to
/// the build that asked for it, so a late pass for an older intent cannot
/// overwrite a newer answer; the revision tests pin that behaviour.
///
/// Copied from [publishedCatalogueView].
class PublishedCatalogueViewProvider
    extends AutoDisposeFutureProvider<PublishedCatalogueView> {
  /// The display view: the pure engine applied to the loaded catalogue and the
  /// debounced query intent.
  ///
  /// The engine runs through the injected `PublishedCatalogueQueryRunner` port,
  /// never on the UI isolate in production. Riverpod attributes each result to
  /// the build that asked for it, so a late pass for an older intent cannot
  /// overwrite a newer answer; the revision tests pin that behaviour.
  ///
  /// Copied from [publishedCatalogueView].
  PublishedCatalogueViewProvider(String siteUrl)
    : this._internal(
        (ref) =>
            publishedCatalogueView(ref as PublishedCatalogueViewRef, siteUrl),
        from: publishedCatalogueViewProvider,
        name: r'publishedCatalogueViewProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueViewHash,
        dependencies: PublishedCatalogueViewFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueViewFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueViewProvider._internal(
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
    FutureOr<PublishedCatalogueView> Function(
      PublishedCatalogueViewRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueViewProvider._internal(
        (ref) => create(ref as PublishedCatalogueViewRef),
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
  AutoDisposeFutureProviderElement<PublishedCatalogueView> createElement() {
    return _PublishedCatalogueViewProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueViewProvider && other.siteUrl == siteUrl;
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
mixin PublishedCatalogueViewRef
    on AutoDisposeFutureProviderRef<PublishedCatalogueView> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueViewProviderElement
    extends AutoDisposeFutureProviderElement<PublishedCatalogueView>
    with PublishedCatalogueViewRef {
  _PublishedCatalogueViewProviderElement(super.provider);

  @override
  String get siteUrl => (origin as PublishedCatalogueViewProvider).siteUrl;
}

String _$publishedCatalogueLanguagesHash() =>
    r'aef43b69912d9d9cb11750d327ed33406648d3ff';

/// The language facet for one catalogue: distinct trimmed values, sorted and
/// case-insensitively deduplicated. Computed once per decoded payload, not
/// once per query.
///
/// Copied from [publishedCatalogueLanguages].
@ProviderFor(publishedCatalogueLanguages)
const publishedCatalogueLanguagesProvider = PublishedCatalogueLanguagesFamily();

/// The language facet for one catalogue: distinct trimmed values, sorted and
/// case-insensitively deduplicated. Computed once per decoded payload, not
/// once per query.
///
/// Copied from [publishedCatalogueLanguages].
class PublishedCatalogueLanguagesFamily extends Family<List<String>> {
  /// The language facet for one catalogue: distinct trimmed values, sorted and
  /// case-insensitively deduplicated. Computed once per decoded payload, not
  /// once per query.
  ///
  /// Copied from [publishedCatalogueLanguages].
  const PublishedCatalogueLanguagesFamily();

  /// The language facet for one catalogue: distinct trimmed values, sorted and
  /// case-insensitively deduplicated. Computed once per decoded payload, not
  /// once per query.
  ///
  /// Copied from [publishedCatalogueLanguages].
  PublishedCatalogueLanguagesProvider call(String siteUrl) {
    return PublishedCatalogueLanguagesProvider(siteUrl);
  }

  @override
  PublishedCatalogueLanguagesProvider getProviderOverride(
    covariant PublishedCatalogueLanguagesProvider provider,
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
  String? get name => r'publishedCatalogueLanguagesProvider';
}

/// The language facet for one catalogue: distinct trimmed values, sorted and
/// case-insensitively deduplicated. Computed once per decoded payload, not
/// once per query.
///
/// Copied from [publishedCatalogueLanguages].
class PublishedCatalogueLanguagesProvider
    extends AutoDisposeProvider<List<String>> {
  /// The language facet for one catalogue: distinct trimmed values, sorted and
  /// case-insensitively deduplicated. Computed once per decoded payload, not
  /// once per query.
  ///
  /// Copied from [publishedCatalogueLanguages].
  PublishedCatalogueLanguagesProvider(String siteUrl)
    : this._internal(
        (ref) => publishedCatalogueLanguages(
          ref as PublishedCatalogueLanguagesRef,
          siteUrl,
        ),
        from: publishedCatalogueLanguagesProvider,
        name: r'publishedCatalogueLanguagesProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueLanguagesHash,
        dependencies: PublishedCatalogueLanguagesFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueLanguagesFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueLanguagesProvider._internal(
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
    List<String> Function(PublishedCatalogueLanguagesRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueLanguagesProvider._internal(
        (ref) => create(ref as PublishedCatalogueLanguagesRef),
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
  AutoDisposeProviderElement<List<String>> createElement() {
    return _PublishedCatalogueLanguagesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueLanguagesProvider &&
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
mixin PublishedCatalogueLanguagesRef on AutoDisposeProviderRef<List<String>> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueLanguagesProviderElement
    extends AutoDisposeProviderElement<List<String>>
    with PublishedCatalogueLanguagesRef {
  _PublishedCatalogueLanguagesProviderElement(super.provider);

  @override
  String get siteUrl => (origin as PublishedCatalogueLanguagesProvider).siteUrl;
}

String _$publishedCatalogueQueryControllerHash() =>
    r'1fd4f144154e306d1e1499d9fba5dd4c2f0be83b';

abstract class _$PublishedCatalogueQueryController
    extends BuildlessAutoDisposeNotifier<PublishedCatalogueQueryState> {
  late final String siteUrl;

  PublishedCatalogueQueryState build(String siteUrl);
}

/// Holds the viewer's search/filter/sort intent for one library session.
///
/// Copied from [PublishedCatalogueQueryController].
@ProviderFor(PublishedCatalogueQueryController)
const publishedCatalogueQueryControllerProvider =
    PublishedCatalogueQueryControllerFamily();

/// Holds the viewer's search/filter/sort intent for one library session.
///
/// Copied from [PublishedCatalogueQueryController].
class PublishedCatalogueQueryControllerFamily
    extends Family<PublishedCatalogueQueryState> {
  /// Holds the viewer's search/filter/sort intent for one library session.
  ///
  /// Copied from [PublishedCatalogueQueryController].
  const PublishedCatalogueQueryControllerFamily();

  /// Holds the viewer's search/filter/sort intent for one library session.
  ///
  /// Copied from [PublishedCatalogueQueryController].
  PublishedCatalogueQueryControllerProvider call(String siteUrl) {
    return PublishedCatalogueQueryControllerProvider(siteUrl);
  }

  @override
  PublishedCatalogueQueryControllerProvider getProviderOverride(
    covariant PublishedCatalogueQueryControllerProvider provider,
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
  String? get name => r'publishedCatalogueQueryControllerProvider';
}

/// Holds the viewer's search/filter/sort intent for one library session.
///
/// Copied from [PublishedCatalogueQueryController].
class PublishedCatalogueQueryControllerProvider
    extends
        AutoDisposeNotifierProviderImpl<
          PublishedCatalogueQueryController,
          PublishedCatalogueQueryState
        > {
  /// Holds the viewer's search/filter/sort intent for one library session.
  ///
  /// Copied from [PublishedCatalogueQueryController].
  PublishedCatalogueQueryControllerProvider(String siteUrl)
    : this._internal(
        () => PublishedCatalogueQueryController()..siteUrl = siteUrl,
        from: publishedCatalogueQueryControllerProvider,
        name: r'publishedCatalogueQueryControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$publishedCatalogueQueryControllerHash,
        dependencies: PublishedCatalogueQueryControllerFamily._dependencies,
        allTransitiveDependencies:
            PublishedCatalogueQueryControllerFamily._allTransitiveDependencies,
        siteUrl: siteUrl,
      );

  PublishedCatalogueQueryControllerProvider._internal(
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
  PublishedCatalogueQueryState runNotifierBuild(
    covariant PublishedCatalogueQueryController notifier,
  ) {
    return notifier.build(siteUrl);
  }

  @override
  Override overrideWith(PublishedCatalogueQueryController Function() create) {
    return ProviderOverride(
      origin: this,
      override: PublishedCatalogueQueryControllerProvider._internal(
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
    PublishedCatalogueQueryController,
    PublishedCatalogueQueryState
  >
  createElement() {
    return _PublishedCatalogueQueryControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PublishedCatalogueQueryControllerProvider &&
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
mixin PublishedCatalogueQueryControllerRef
    on AutoDisposeNotifierProviderRef<PublishedCatalogueQueryState> {
  /// The parameter `siteUrl` of this provider.
  String get siteUrl;
}

class _PublishedCatalogueQueryControllerProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          PublishedCatalogueQueryController,
          PublishedCatalogueQueryState
        >
    with PublishedCatalogueQueryControllerRef {
  _PublishedCatalogueQueryControllerProviderElement(super.provider);

  @override
  String get siteUrl =>
      (origin as PublishedCatalogueQueryControllerProvider).siteUrl;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
