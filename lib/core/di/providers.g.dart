// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bookmarksRepositoryHash() =>
    r'1a568adef0d936272410aa4927e2fa94e78f1957';

/// Library-bookmarks persistence (other libraries' published sites). Non-secret
/// flat list in shared_preferences — no Drift table/migration.
///
/// Copied from [bookmarksRepository].
@ProviderFor(bookmarksRepository)
final bookmarksRepositoryProvider =
    AutoDisposeFutureProvider<BookmarksRepository>.internal(
      bookmarksRepository,
      name: r'bookmarksRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$bookmarksRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookmarksRepositoryRef =
    AutoDisposeFutureProviderRef<BookmarksRepository>;
String _$appUpdateServiceHash() => r'509cbf430ce87b34b1651c01164197a9f0c689dc';

/// The Play in-app update seam (S35). The real service gates itself to
/// Android + the `play` applicationId (the fdroid flavor has no Play listing
/// and stays inert) and degrades to silence on every platform failure.
/// Overridden with a fake in tests.
///
/// Copied from [appUpdateService].
@ProviderFor(appUpdateService)
final appUpdateServiceProvider = AutoDisposeProvider<AppUpdateService>.internal(
  appUpdateService,
  name: r'appUpdateServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appUpdateServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppUpdateServiceRef = AutoDisposeProviderRef<AppUpdateService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
