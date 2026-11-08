// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_watch_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$eventsWatchIncarnationGeneratorHash() =>
    r'58e374434a0470afb754bba8cd8ed00fc291aaf6';

/// Injectable incarnation generator (tests make it deterministic).
///
/// Copied from [eventsWatchIncarnationGenerator].
@ProviderFor(eventsWatchIncarnationGenerator)
final eventsWatchIncarnationGeneratorProvider =
    Provider<IncarnationGenerator>.internal(
      eventsWatchIncarnationGenerator,
      name: r'eventsWatchIncarnationGeneratorProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsWatchIncarnationGeneratorHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsWatchIncarnationGeneratorRef = ProviderRef<IncarnationGenerator>;
String _$eventsWatchControllerHash() =>
    r'9a797217bfe0faaaa0eb6709c83480b45557ca8b';

/// See the file header.
///
/// keepAlive: the controller is the feature's single foreground writer and
/// must outlive any one screen; disposing it mid-action could let a second
/// instance write settings concurrently.
///
/// Copied from [EventsWatchController].
@ProviderFor(EventsWatchController)
final eventsWatchControllerProvider =
    AsyncNotifierProvider<EventsWatchController, EventsWatchView>.internal(
      EventsWatchController.new,
      name: r'eventsWatchControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsWatchControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$EventsWatchController = AsyncNotifier<EventsWatchView>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
