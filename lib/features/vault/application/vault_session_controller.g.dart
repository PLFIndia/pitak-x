// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vaultSessionControllerHash() =>
    r'6b91587136cf1ec48a92c782000344754cba4040';

/// Holds the persistent vault's [VaultSessionState] across navigation.
///
/// `keepAlive`: the unlocked session (and its held passphrase) must survive
/// screen changes; it is torn down explicitly via [lock] or when the app
/// disposes the provider (which wipes the passphrase via `ref.onDispose`).
///
/// Copied from [VaultSessionController].
@ProviderFor(VaultSessionController)
final vaultSessionControllerProvider =
    AsyncNotifierProvider<VaultSessionController, VaultSessionState>.internal(
      VaultSessionController.new,
      name: r'vaultSessionControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$vaultSessionControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$VaultSessionController = AsyncNotifier<VaultSessionState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
