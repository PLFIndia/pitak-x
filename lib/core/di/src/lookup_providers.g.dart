// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lookup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$isbnCacheHash() => r'b428f9e867c0431f09959101b86b0727f936da90';

/// Session-scoped ISBN lookup cache (#30). Non-secret public metadata.
///
/// Copied from [isbnCache].
@ProviderFor(isbnCache)
final isbnCacheProvider = Provider<IsbnCache>.internal(
  isbnCache,
  name: r'isbnCacheProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isbnCacheHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsbnCacheRef = ProviderRef<IsbnCache>;
String _$lookupKeyStoreHash() => r'4a7fdc4e914d0acab18bc26f72d9f03b8ab0bd90';

/// Optional user-supplied Google Books API key (encrypted at rest, §6.3).
/// keepAlive: tiny, session-stable, and read on every lookup.
///
/// Copied from [lookupKeyStore].
@ProviderFor(lookupKeyStore)
final lookupKeyStoreProvider = Provider<LookupKeyStore>.internal(
  lookupKeyStore,
  name: r'lookupKeyStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$lookupKeyStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LookupKeyStoreRef = ProviderRef<LookupKeyStore>;
String _$isbnLookupServiceHash() => r'4af351513ac4052d00833d4af6a4a39a351eb2d3';

/// ISBN lookup + title search (#29/#30): Open Library primary, Google Books
/// fallback, chained over the cache. Only hit on explicit user action.
///
/// Copied from [isbnLookupService].
@ProviderFor(isbnLookupService)
final isbnLookupServiceProvider =
    AutoDisposeProvider<IsbnLookupService>.internal(
      isbnLookupService,
      name: r'isbnLookupServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$isbnLookupServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IsbnLookupServiceRef = AutoDisposeProviderRef<IsbnLookupService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
