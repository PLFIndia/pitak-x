// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_refresh_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$networkRefreshControllerHash() =>
    r'771607ad786fccf1d3ab84a2f0a5bf0e3c353f34';

/// Runs network refreshes: state is `AsyncLoading` while a run is in flight,
/// otherwise the last [RefreshReport] (null = never refreshed yet).
///
/// Copied from [NetworkRefreshController].
@ProviderFor(NetworkRefreshController)
final networkRefreshControllerProvider =
    AsyncNotifierProvider<NetworkRefreshController, RefreshReport?>.internal(
      NetworkRefreshController.new,
      name: r'networkRefreshControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$networkRefreshControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$NetworkRefreshController = AsyncNotifier<RefreshReport?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
