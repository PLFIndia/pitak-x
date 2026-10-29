// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloudflare_connection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$cloudflareConnectionControllerHash() =>
    r'9c116e92293d1229ca42abaa29eb811671481301';

/// Owns Cloudflare setup while presentation only renders and answers prompts.
///
/// Copied from [CloudflareConnectionController].
@ProviderFor(CloudflareConnectionController)
final cloudflareConnectionControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      CloudflareConnectionController,
      CloudflareConnectionUi
    >.internal(
      CloudflareConnectionController.new,
      name: r'cloudflareConnectionControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$cloudflareConnectionControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$CloudflareConnectionController =
    AutoDisposeAsyncNotifier<CloudflareConnectionUi>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
