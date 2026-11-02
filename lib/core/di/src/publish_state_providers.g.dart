// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'publish_state_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$publishStateBackupSourceHash() =>
    r'f11f8c9d9a6064e0d7e5badbc698b10c7f5582ed';

/// Reads this phone's publishing record for a backup (`publish_state.json`).
///
/// Read-only: no queue, no credential, no network (see
/// `PublishStateBackupReader` for why it does not wait for a publish).
///
/// Copied from [publishStateBackupSource].
@ProviderFor(publishStateBackupSource)
final publishStateBackupSourceProvider =
    AutoDisposeFutureProvider<PublishStateBackupSource>.internal(
      publishStateBackupSource,
      name: r'publishStateBackupSourceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishStateBackupSourceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishStateBackupSourceRef =
    AutoDisposeFutureProviderRef<PublishStateBackupSource>;
String _$publishStateAdopterHash() =>
    r'7ade182f66aa766cf4f87ada6110deef82106d2d';

/// Adopts a restored backup's publishing record on a phone that has not
/// published yet (plan CV7).
///
/// The ONE place that hands out the replaceable salt store. The adopter runs
/// through `CatalogueKeysReset.beforeIdsChange`, so it holds the app-wide
/// publish queue and the lane forgets keys made with the old salt
/// (`publish_salt_invariant_test.dart` pins this wiring).
///
/// Copied from [publishStateAdopter].
@ProviderFor(publishStateAdopter)
final publishStateAdopterProvider =
    AutoDisposeFutureProvider<PublishStateAdopter>.internal(
      publishStateAdopter,
      name: r'publishStateAdopterProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishStateAdopterHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishStateAdopterRef =
    AutoDisposeFutureProviderRef<PublishStateAdopter>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
