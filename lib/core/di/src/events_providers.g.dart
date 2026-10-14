// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$eventsPosterReaderHash() =>
    r'8c4ec79276a4cd17122505a0b19484db9e750563';

/// Event-poster file reader for publishing (N14): file IO injected as the
/// `PosterBytesReader` port; the events controller no longer touches dart:io.
///
/// Copied from [eventsPosterReader].
@ProviderFor(eventsPosterReader)
final eventsPosterReaderProvider =
    AutoDisposeFutureProvider<Future<List<int>?> Function(String)>.internal(
      eventsPosterReader,
      name: r'eventsPosterReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsPosterReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsPosterReaderRef =
    AutoDisposeFutureProviderRef<Future<List<int>?> Function(String)>;
String _$eventsRepositoryHash() => r'1394ab4191a80a78c84e94f9d87022e666648a6d';

/// Events (poster) persistence: `events.json` + `posters/<uuid>.jpg` under the
/// app docs dir. Poster images are downscaled (EXIF/GPS stripped) before save.
/// Poster bounds are larger + portrait-leaning vs the 2:3 book-cover default.
///
/// Copied from [eventsRepository].
@ProviderFor(eventsRepository)
final eventsRepositoryProvider =
    AutoDisposeFutureProvider<EventsRepository>.internal(
      eventsRepository,
      name: r'eventsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsRepositoryRef = AutoDisposeFutureProviderRef<EventsRepository>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
