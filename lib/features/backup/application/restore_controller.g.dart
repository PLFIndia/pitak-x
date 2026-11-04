// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restore_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$restoreControllerHash() => r'2367302110fbf7a6175db3d55c4bc049ecad3d27';

/// Drives a one-shot restore and surfaces its [RestoreSummary].
///
/// Lifecycle ownership (N11): a restore is an authoritative overwrite that
/// must FINISH once started, so the run is owned here, not by the page —
/// modelled on `PublishController`/`ImportController`:
///  - the provider is `keepAlive` (review item 11): navigating away cannot
///    dispose it mid-restore, swallow the terminal state, or let a rebuilt
///    page start a SECOND concurrent restore — and the terminal
///    success/failure stays visible when Restore is reopened until the user
///    chooses a new archive ([clearResult]) or starts a new restore;
///  - `_running` refuses a second call outright;
///  - an unexpected throw becomes a typed `AsyncError(UnexpectedFailure)`
///    instead of escaping into the page's unawaited future;
///  - the post-success list refresh is invalidated HERE (next to the vault
///    session invalidation), so it happens even when the page is gone.
///
/// keepAlive is safe here: the controller holds no secret (the passphrase is
/// wiped in `restore`'s `finally`) and a [RestoreSummary] is only counts and
/// outcome flags.
///
/// Copied from [RestoreController].
@ProviderFor(RestoreController)
final restoreControllerProvider =
    AsyncNotifierProvider<RestoreController, RestoreSummary?>.internal(
      RestoreController.new,
      name: r'restoreControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$restoreControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RestoreController = AsyncNotifier<RestoreSummary?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
