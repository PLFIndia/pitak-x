// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_update_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appUpdateServiceHash() => r'509cbf430ce87b34b1651c01164197a9f0c689dc';

/// The Play in-app update seam (S35). See the file header for the flavor
/// gating; overridden with a fake in tests.
///
/// Copied from [appUpdateService].
@ProviderFor(appUpdateService)
final appUpdateServiceProvider = AutoDisposeProvider<AppUpdateService>.internal(
  appUpdateService,
  name: r'appUpdateServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appUpdateServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppUpdateServiceRef = AutoDisposeProviderRef<AppUpdateService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
