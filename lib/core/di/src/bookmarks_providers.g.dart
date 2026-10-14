// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmarks_providers.dart';

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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
