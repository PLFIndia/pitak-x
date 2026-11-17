// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resource_notice_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$backupResourceNoticeHash() =>
    r'2bf6dc3a923fcafb716a24773637d727818b06d0';

/// What a backup of the library as it is now needs, against what this
/// device has.
///
/// Copied from [backupResourceNotice].
@ProviderFor(backupResourceNotice)
final backupResourceNoticeProvider =
    AutoDisposeFutureProvider<ResourceNotice>.internal(
      backupResourceNotice,
      name: r'backupResourceNoticeProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$backupResourceNoticeHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BackupResourceNoticeRef = AutoDisposeFutureProviderRef<ResourceNotice>;
String _$restoreResourceNoticeHash() =>
    r'8b4b2a6dba332e06f681936576c0c55f40daa4e4';

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

/// What a restore of the chosen backup still needs, against what this
/// device has. [archive] is what the inspection of the backup found
/// (`ArchiveInspection.sizes`).
///
/// Copied from [restoreResourceNotice].
@ProviderFor(restoreResourceNotice)
const restoreResourceNoticeProvider = RestoreResourceNoticeFamily();

/// What a restore of the chosen backup still needs, against what this
/// device has. [archive] is what the inspection of the backup found
/// (`ArchiveInspection.sizes`).
///
/// Copied from [restoreResourceNotice].
class RestoreResourceNoticeFamily extends Family<AsyncValue<ResourceNotice>> {
  /// What a restore of the chosen backup still needs, against what this
  /// device has. [archive] is what the inspection of the backup found
  /// (`ArchiveInspection.sizes`).
  ///
  /// Copied from [restoreResourceNotice].
  const RestoreResourceNoticeFamily();

  /// What a restore of the chosen backup still needs, against what this
  /// device has. [archive] is what the inspection of the backup found
  /// (`ArchiveInspection.sizes`).
  ///
  /// Copied from [restoreResourceNotice].
  RestoreResourceNoticeProvider call(
    ({int databaseBytes, bool hasCovers, bool hasVault, int takenBytes})
    archive,
  ) {
    return RestoreResourceNoticeProvider(archive);
  }

  @override
  RestoreResourceNoticeProvider getProviderOverride(
    covariant RestoreResourceNoticeProvider provider,
  ) {
    return call(provider.archive);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'restoreResourceNoticeProvider';
}

/// What a restore of the chosen backup still needs, against what this
/// device has. [archive] is what the inspection of the backup found
/// (`ArchiveInspection.sizes`).
///
/// Copied from [restoreResourceNotice].
class RestoreResourceNoticeProvider
    extends AutoDisposeFutureProvider<ResourceNotice> {
  /// What a restore of the chosen backup still needs, against what this
  /// device has. [archive] is what the inspection of the backup found
  /// (`ArchiveInspection.sizes`).
  ///
  /// Copied from [restoreResourceNotice].
  RestoreResourceNoticeProvider(
    ({int databaseBytes, bool hasCovers, bool hasVault, int takenBytes})
    archive,
  ) : this._internal(
        (ref) =>
            restoreResourceNotice(ref as RestoreResourceNoticeRef, archive),
        from: restoreResourceNoticeProvider,
        name: r'restoreResourceNoticeProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$restoreResourceNoticeHash,
        dependencies: RestoreResourceNoticeFamily._dependencies,
        allTransitiveDependencies:
            RestoreResourceNoticeFamily._allTransitiveDependencies,
        archive: archive,
      );

  RestoreResourceNoticeProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.archive,
  }) : super.internal();

  final ({int databaseBytes, bool hasCovers, bool hasVault, int takenBytes})
  archive;

  @override
  Override overrideWith(
    FutureOr<ResourceNotice> Function(RestoreResourceNoticeRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: RestoreResourceNoticeProvider._internal(
        (ref) => create(ref as RestoreResourceNoticeRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        archive: archive,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<ResourceNotice> createElement() {
    return _RestoreResourceNoticeProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is RestoreResourceNoticeProvider && other.archive == archive;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, archive.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin RestoreResourceNoticeRef on AutoDisposeFutureProviderRef<ResourceNotice> {
  /// The parameter `archive` of this provider.
  ({int databaseBytes, bool hasCovers, bool hasVault, int takenBytes})
  get archive;
}

class _RestoreResourceNoticeProviderElement
    extends AutoDisposeFutureProviderElement<ResourceNotice>
    with RestoreResourceNoticeRef {
  _RestoreResourceNoticeProviderElement(super.provider);

  @override
  ({int databaseBytes, bool hasCovers, bool hasVault, int takenBytes})
  get archive => (origin as RestoreResourceNoticeProvider).archive;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
