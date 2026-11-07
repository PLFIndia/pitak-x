// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_watch_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$eventsWatchSupportedHash() =>
    r'c1d371e0e01ee528937ae69832b38c517299a7ab';

/// True where background alerts exist at all (Android only).
///
/// Copied from [eventsWatchSupported].
@ProviderFor(eventsWatchSupported)
final eventsWatchSupportedProvider = Provider<bool>.internal(
  eventsWatchSupported,
  name: r'eventsWatchSupportedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$eventsWatchSupportedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchSupportedRef = ProviderRef<bool>;
String _$eventsWatchSettingsStoreHash() =>
    r'1f4fef59e7237fab3890dcdc78694a1b33ad20b8';

/// Foreground-owned settings document store.
///
/// Copied from [eventsWatchSettingsStore].
@ProviderFor(eventsWatchSettingsStore)
final eventsWatchSettingsStoreProvider =
    FutureProvider<EventsWatchSettingsStore>.internal(
      eventsWatchSettingsStore,
      name: r'eventsWatchSettingsStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsWatchSettingsStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchSettingsStoreRef =
    FutureProviderRef<EventsWatchSettingsStore>;
String _$eventsWatchStateStoreHash() =>
    r'85f586c47ea3f5ce606231e2428b20fd24ee2dae';

/// Worker-owned state document store (the foreground only READS it).
///
/// Copied from [eventsWatchStateStore].
@ProviderFor(eventsWatchStateStore)
final eventsWatchStateStoreProvider =
    FutureProvider<EventsWatchStateStore>.internal(
      eventsWatchStateStore,
      name: r'eventsWatchStateStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsWatchStateStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchStateStoreRef = FutureProviderRef<EventsWatchStateStore>;
String _$watchedLibrariesSourceHash() =>
    r'068d084c63f8fd1974362b4e4ab39d748bc0e7f5';

/// Strict read-only source of saved libraries. Peeks the active generation
/// on every read; never uses the Drift connection.
///
/// Copied from [watchedLibrariesSource].
@ProviderFor(watchedLibrariesSource)
final watchedLibrariesSourceProvider =
    FutureProvider<WatchedLibrariesSource>.internal(
      watchedLibrariesSource,
      name: r'watchedLibrariesSourceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$watchedLibrariesSourceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WatchedLibrariesSourceRef = FutureProviderRef<WatchedLibrariesSource>;
String _$androidEventsNotifierHash() =>
    r'87ef9e1147639a0af57ce172c27a63d71540b3ca';

/// The real notifier on Android; a never-deliverable one elsewhere.
///
/// Copied from [androidEventsNotifier].
@ProviderFor(androidEventsNotifier)
final androidEventsNotifierProvider =
    Provider<LocalNotificationsNotifier?>.internal(
      androidEventsNotifier,
      name: r'androidEventsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$androidEventsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AndroidEventsNotifierRef = ProviderRef<LocalNotificationsNotifier?>;
String _$eventsWatchNotifierHash() =>
    r'8dd5f8dcf846dd32a982c4879cb16f7121688552';

/// Port view of [androidEventsNotifier].
///
/// Copied from [eventsWatchNotifier].
@ProviderFor(eventsWatchNotifier)
final eventsWatchNotifierProvider = Provider<LocalNotifier>.internal(
  eventsWatchNotifier,
  name: r'eventsWatchNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$eventsWatchNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchNotifierRef = ProviderRef<LocalNotifier>;
String _$eventsWatchPermissionRequestHash() =>
    r'1044036501521d3c341dd09f21442fdf47ac8058';

/// Runtime permission prompt (Android 13+); refused elsewhere.
///
/// Copied from [eventsWatchPermissionRequest].
@ProviderFor(eventsWatchPermissionRequest)
final eventsWatchPermissionRequestProvider =
    Provider<NotificationPermissionRequest>.internal(
      eventsWatchPermissionRequest,
      name: r'eventsWatchPermissionRequestProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsWatchPermissionRequestHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchPermissionRequestRef =
    ProviderRef<NotificationPermissionRequest>;
String _$eventsWatchSchedulerHash() =>
    r'c6c803880328791a3b6cd4577b7823dbc483acf4';

/// Periodic job scheduler.
///
/// Copied from [eventsWatchScheduler].
@ProviderFor(eventsWatchScheduler)
final eventsWatchSchedulerProvider = Provider<EventsWatchScheduler>.internal(
  eventsWatchScheduler,
  name: r'eventsWatchSchedulerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$eventsWatchSchedulerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchSchedulerRef = ProviderRef<EventsWatchScheduler>;
String _$eventsWatchClockHash() => r'f2002eb0977f1fe97d6cd32e053230d612cae424';

/// Wall clock + stopwatch.
///
/// Copied from [eventsWatchClock].
@ProviderFor(eventsWatchClock)
final eventsWatchClockProvider = Provider<WatchClock>.internal(
  eventsWatchClock,
  name: r'eventsWatchClockProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$eventsWatchClockHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchClockRef = ProviderRef<WatchClock>;
String _$eventsWatchBootstrapHash() =>
    r'298172f61796f3b698693a8559776c48780e98f1';

/// Android: initialize plugins; elsewhere: nothing.
///
/// Copied from [eventsWatchBootstrap].
@ProviderFor(eventsWatchBootstrap)
final eventsWatchBootstrapProvider = Provider<EventsWatchBootstrap>.internal(
  eventsWatchBootstrap,
  name: r'eventsWatchBootstrapProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$eventsWatchBootstrapHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchBootstrapRef = ProviderRef<EventsWatchBootstrap>;
String _$eventsWatchRouteQueueHash() =>
    r'9a3a82976bf7d3e658db053a0adc10509a4437f4';

/// A notification payload waiting for the app to be ready (providers
/// built, app lock passed). Consumed exactly once.
///
/// Copied from [EventsWatchRouteQueue].
@ProviderFor(EventsWatchRouteQueue)
final eventsWatchRouteQueueProvider =
    NotifierProvider<EventsWatchRouteQueue, String?>.internal(
      EventsWatchRouteQueue.new,
      name: r'eventsWatchRouteQueueProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsWatchRouteQueueHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$EventsWatchRouteQueue = Notifier<String?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
