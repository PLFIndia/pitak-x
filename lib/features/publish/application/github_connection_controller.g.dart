// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'github_connection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$gitHubConnectionControllerHash() =>
    r'd69d6628d872ce0c35352fbb174848fe47765065';

/// Owns the GitHub connection tab's state machine (application layer).
///
/// The page watches this provider and only renders the state + forwards
/// intents (sign-in tapped → [signIn], repo picked → [selectRepo], …).
///
/// Copied from [GitHubConnectionController].
@ProviderFor(GitHubConnectionController)
final gitHubConnectionControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      GitHubConnectionController,
      GitHubConnectionUi
    >.internal(
      GitHubConnectionController.new,
      name: r'gitHubConnectionControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$gitHubConnectionControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GitHubConnectionController =
    AutoDisposeAsyncNotifier<GitHubConnectionUi>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
