// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vaultControllerHash() => r'bc16d93fc8c6644bcb6b9c5c73e1e96021924d99';

/// Drives a one-shot read-only vault unlock and surfaces its [VaultData].
///
/// Copied from [VaultController].
@ProviderFor(VaultController)
final vaultControllerProvider =
    AutoDisposeAsyncNotifierProvider<VaultController, VaultData?>.internal(
      VaultController.new,
      name: r'vaultControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$vaultControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$VaultController = AutoDisposeAsyncNotifier<VaultData?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
