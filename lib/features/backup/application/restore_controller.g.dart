// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restore_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$restoreProgressHash() => r'3edcf497fdb074bc09afdd36c5aa3c478406f3fe';

/// How many cover pictures the running restore has written, of how many
/// (decision D27); null when no restore runs, and before its first cover.
///
/// A notifier of its own, next to the controller, because a restore
/// outlives its page: a page that is reopened during a restore shows the
/// count again. Only [RestoreController] sets it.
///
/// keepAlive (justified): for the same reason as the controller. The value
/// is two whole numbers; it holds nothing secret.
///
/// Copied from [RestoreProgress].
@ProviderFor(RestoreProgress)
final restoreProgressProvider =
    NotifierProvider<RestoreProgress, BackupProgress?>.internal(
      RestoreProgress.new,
      name: r'restoreProgressProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$restoreProgressHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RestoreProgress = Notifier<BackupProgress?>;
String _$restoreControllerHash() => r'52bd6d61a6b84ca17ed6b313400d951c7abd386c';

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
/// wiped in `restore`'s `finally`). A [RestoreSummary] holds counts and
/// outcome flags and some of the user's own catalogue data: the identity
/// name, the saved-libraries rows, and the titles of the items whose cover
/// picture was left out (D23). All of it is shown on the Restore screen
/// only, never logged, and goes when a new file is chosen.
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
