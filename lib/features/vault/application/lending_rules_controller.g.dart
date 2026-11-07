// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lending_rules_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$lendingRulesControllerHash() =>
    r'880033935105633ff0f9173cd882f14952aa47db';

/// Auto-dispose screen state; the policy itself remains in SharedPreferences.
///
/// Copied from [LendingRulesController].
@ProviderFor(LendingRulesController)
final lendingRulesControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      LendingRulesController,
      BorrowerLimitPolicy
    >.internal(
      LendingRulesController.new,
      name: r'lendingRulesControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$lendingRulesControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LendingRulesController =
    AutoDisposeAsyncNotifier<BorrowerLimitPolicy>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
