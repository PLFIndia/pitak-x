// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'availability_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$availabilityLaneActivatedHash() =>
    r'6cead7dc8dfd161acb41ffa8b95f190e5b9a8de8';

/// Whether this build runs the availability lane (plan A.6 #58).
///
/// **False until plan S8**, which turns it on in the same change as the
/// guide copy (AV16: the copy must match what the app does) and starts the
/// lane in `main.dart`. While it is false:
///  - every publish treats the lane as OFF (`PublishController.availability`
///    returns the removal), exactly as before S6;
///  - the Settings switch and the status row are not shown, so nothing
///    promises an update the app does not make;
///  - nothing starts the lane notifier.
///
/// Tests override it to exercise the lane, the switch and the row.
///
/// Copied from [availabilityLaneActivated].
@ProviderFor(availabilityLaneActivated)
final availabilityLaneActivatedProvider = Provider<bool>.internal(
  availabilityLaneActivated,
  name: r'availabilityLaneActivatedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$availabilityLaneActivatedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AvailabilityLaneActivatedRef = ProviderRef<bool>;
String _$availabilityItemKeysHash() =>
    r'130aaabb25d8c33b346f6a450a43b9681ff2fe56';

/// Item keys for the lane, over the SAME salt store the snapshot builder
/// uses (ADR 0019 Decision 3), so lane keys and `books.json` keys agree.
///
/// Copied from [availabilityItemKeys].
@ProviderFor(availabilityItemKeys)
final availabilityItemKeysProvider =
    AutoDisposeProvider<PublishItemKeys>.internal(
      availabilityItemKeys,
      name: r'availabilityItemKeysProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$availabilityItemKeysHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AvailabilityItemKeysRef = AutoDisposeProviderRef<PublishItemKeys>;
String _$publishAvailabilityUseCaseHash() =>
    r'd1125415c4544c6fffba547e917f701ee5b59032';

/// The GitHub availability-only publish (plan S4).
///
/// Copied from [publishAvailabilityUseCase].
@ProviderFor(publishAvailabilityUseCase)
final publishAvailabilityUseCaseProvider =
    AutoDisposeFutureProvider<PublishAvailabilityUseCase>.internal(
      publishAvailabilityUseCase,
      name: r'publishAvailabilityUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishAvailabilityUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishAvailabilityUseCaseRef =
    AutoDisposeFutureProviderRef<PublishAvailabilityUseCase>;
String _$publishAvailabilityToCloudflareUseCaseHash() =>
    r'206470d3add0b6b3695e6393810600e898835086';

/// The Cloudflare availability-only publish (plan S5), over the same
/// collaborators as the ordinary Cloudflare publish.
///
/// Copied from [publishAvailabilityToCloudflareUseCase].
@ProviderFor(publishAvailabilityToCloudflareUseCase)
final publishAvailabilityToCloudflareUseCaseProvider =
    AutoDisposeFutureProvider<PublishAvailabilityToCloudflareUseCase>.internal(
      publishAvailabilityToCloudflareUseCase,
      name: r'publishAvailabilityToCloudflareUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishAvailabilityToCloudflareUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishAvailabilityToCloudflareUseCaseRef =
    AutoDisposeFutureProviderRef<PublishAvailabilityToCloudflareUseCase>;
String _$availabilityPublishRunnerHash() =>
    r'3345e58fd7af2a0f53adcadec76a4c08d118a370';

/// Runs one lane publish inside the publish queue, for the active host.
///
/// Copied from [availabilityPublishRunner].
@ProviderFor(availabilityPublishRunner)
final availabilityPublishRunnerProvider =
    AutoDisposeFutureProvider<AvailabilityPublishRunner>.internal(
      availabilityPublishRunner,
      name: r'availabilityPublishRunnerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$availabilityPublishRunnerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AvailabilityPublishRunnerRef =
    AutoDisposeFutureProviderRef<AvailabilityPublishRunner>;
String _$catalogueKeysResetHash() =>
    r'fd8e85ef9b97911c1bb18334ba74b397b67b1b55';

/// The guard every flow that changes what item ids name runs through
/// (`CatalogueIdsChangeGuard`; plan J9): restore and overwrite merge.
///
/// keepAlive: it is captured by those flows' providers and its callback
/// uses this provider's own `ref` after they finish, so it must outlive
/// them. It holds no secret: two file-backed records and the lane store.
///
/// Copied from [catalogueKeysReset].
@ProviderFor(catalogueKeysReset)
final catalogueKeysResetProvider = FutureProvider<CatalogueKeysReset>.internal(
  catalogueKeysReset,
  name: r'catalogueKeysResetProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$catalogueKeysResetHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CatalogueKeysResetRef = FutureProviderRef<CatalogueKeysReset>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
