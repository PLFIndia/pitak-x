// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appDatabaseHash() => r'629041a8bb606751ed78ae4b41cea55108033206';

/// The non-secret Drift database (books + wishlist), opened inside the active
/// data generation (M02) — switching generations closes and reopens it.
///
/// `keepAlive`: the open DB must survive navigation; reopening per-screen would
/// thrash the connection. Closed when the provider is finally disposed.
///
/// Copied from [appDatabase].
@ProviderFor(appDatabase)
final appDatabaseProvider = FutureProvider<AppDatabase>.internal(
  appDatabase,
  name: r'appDatabaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appDatabaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppDatabaseRef = FutureProviderRef<AppDatabase>;
String _$coversDirHash() => r'aa856a5a2f60d599ae78e5ef83102f4a57d5daab';

/// Absolute path to the covers directory inside the active data generation
/// (M02), where local book covers are stored. Used by cover-rendering widgets.
///
/// Copied from [coversDir].
@ProviderFor(coversDir)
final coversDirProvider = AutoDisposeFutureProvider<String>.internal(
  coversDir,
  name: r'coversDirProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$coversDirHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CoversDirRef = AutoDisposeFutureProviderRef<String>;
String _$sharedPreferencesHash() => r'25eceea0052302f519f44a896409ba30ede45562';

/// The app's shared (non-secret) key-value preferences store.
///
/// Copied from [sharedPreferences].
@ProviderFor(sharedPreferences)
final sharedPreferencesProvider = FutureProvider<SharedPreferences>.internal(
  sharedPreferences,
  name: r'sharedPreferencesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$sharedPreferencesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SharedPreferencesRef = FutureProviderRef<SharedPreferences>;
String _$wishlistRepositoryHash() =>
    r'8e19c7be00a2d645e10c288df3ad187eb80a6bd2';

/// Wishlist repository. Lives with the database bindings (not the wishlist
/// module) to keep the feature-module graph acyclic — see the file header.
///
/// Copied from [wishlistRepository].
@ProviderFor(wishlistRepository)
final wishlistRepositoryProvider =
    AutoDisposeFutureProvider<WishlistRepository>.internal(
      wishlistRepository,
      name: r'wishlistRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$wishlistRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef WishlistRepositoryRef =
    AutoDisposeFutureProviderRef<WishlistRepository>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
