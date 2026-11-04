// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_lock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appLockControllerHash() => r'0581724b29781fe56920b5f7ed65c2e12907f185';

/// Drives the app-lock phase. `keepAlive`: the lock must outlive any widget
/// rebuild — it is the thing protecting the screen while the app is paused.
///
/// Copied from [AppLockController].
@ProviderFor(AppLockController)
final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>.internal(
      AppLockController.new,
      name: r'appLockControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$appLockControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppLockController = Notifier<AppLockState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
