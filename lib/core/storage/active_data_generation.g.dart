// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_data_generation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$activeDataGenerationHash() =>
    r'728d44437c31067ff50afef60990ca9d61c5a113';

/// Resolves (and repairs) the active generation once, then publishes switches.
///
/// Copied from [ActiveDataGeneration].
@ProviderFor(ActiveDataGeneration)
final activeDataGenerationProvider =
    AsyncNotifierProvider<ActiveDataGeneration, DataGeneration>.internal(
      ActiveDataGeneration.new,
      name: r'activeDataGenerationProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activeDataGenerationHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ActiveDataGeneration = AsyncNotifier<DataGeneration>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
