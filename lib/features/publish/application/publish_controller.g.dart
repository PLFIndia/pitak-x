// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'publish_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$publishControllerHash() => r'5b5d074d53c2f9b682853df8711071d6440f332d';

/// Runs a publish and exposes its [PublishResult]; idle until [publish] runs.
///
/// Copied from [PublishController].
@ProviderFor(PublishController)
final publishControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      PublishController,
      PublishResult?
    >.internal(
      PublishController.new,
      name: r'publishControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PublishController = AutoDisposeAsyncNotifier<PublishResult?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
