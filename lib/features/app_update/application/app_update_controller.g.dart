// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_update_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appUpdateControllerHash() =>
    r'6b3467fb592229d74aa038f4f46eb5a61a129406';

/// Drives the check → background-download → restart-offer flow.
///
/// Copied from [AppUpdateController].
@ProviderFor(AppUpdateController)
final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateStatus>.internal(
      AppUpdateController.new,
      name: r'appUpdateControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$appUpdateControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppUpdateController = Notifier<AppUpdateStatus>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
