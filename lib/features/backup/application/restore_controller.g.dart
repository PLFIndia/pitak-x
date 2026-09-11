// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'restore_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$restoreControllerHash() => r'95b45f18ee259160e4029b3f3e5e09f349312d6f';

/// Drives a one-shot restore and surfaces its [RestoreSummary].
///
/// Lifecycle ownership (N11): a restore is an authoritative overwrite that
/// must FINISH once started, so the run is owned here, not by the page —
/// modelled on `PublishController`/`ImportController`:
///  - `ref.keepAlive()` pins this autoDispose element for the run, so
///    navigating away mid-restore cannot dispose it, swallow the terminal
///    state, or let a rebuilt page start a SECOND concurrent restore;
///  - `_running` refuses a second call outright;
///  - an unexpected throw becomes a typed `AsyncError(UnexpectedFailure)`
///    instead of escaping into the page's unawaited future;
///  - the post-success list refresh is invalidated HERE (next to the vault
///    session invalidation), so it happens even when the page is gone.
///
/// Copied from [RestoreController].
@ProviderFor(RestoreController)
final restoreControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      RestoreController,
      RestoreSummary?
    >.internal(
      RestoreController.new,
      name: r'restoreControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$restoreControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RestoreController = AutoDisposeAsyncNotifier<RestoreSummary?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
