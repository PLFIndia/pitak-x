// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appDocsDirHash() => r'e7479780a89d80bc60127b48a09106e777c3d88d';

/// The app's document directory (where the DB + covers live). Resolved once.
///
/// Copied from [appDocsDir].
@ProviderFor(appDocsDir)
final appDocsDirProvider = FutureProvider<Directory>.internal(
  appDocsDir,
  name: r'appDocsDirProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appDocsDirHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppDocsDirRef = FutureProviderRef<Directory>;
String _$appDatabaseHash() => r'6a549fa7d9a9c9bb74f4bb381e2edebdbbba0cb9';

/// The non-secret Drift database (books + wishlist).
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
String _$coversDirHash() => r'5a0975a50009067a5b1ad466771b7bf26581ac96';

/// Absolute path to the covers directory (`<appDocs>/covers`), where local
/// book covers are stored. Resolved once; used by cover-rendering widgets.
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
String _$settingsRepositoryHash() =>
    r'25ead3716ca06d4ab25e03d644f7782042ee2f6b';

/// Non-secret settings persistence (theme, library identity, sort).
///
/// Copied from [settingsRepository].
@ProviderFor(settingsRepository)
final settingsRepositoryProvider =
    AutoDisposeFutureProvider<SettingsRepository>.internal(
      settingsRepository,
      name: r'settingsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$settingsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SettingsRepositoryRef =
    AutoDisposeFutureProviderRef<SettingsRepository>;
String _$bookRepositoryHash() => r'35fe70150a31083fe5f708941458de399870901e';

/// Library books repository.
///
/// Copied from [bookRepository].
@ProviderFor(bookRepository)
final bookRepositoryProvider =
    AutoDisposeFutureProvider<BookRepository>.internal(
      bookRepository,
      name: r'bookRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$bookRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookRepositoryRef = AutoDisposeFutureProviderRef<BookRepository>;
String _$coverStoreHash() => r'5dd39b4bfcd5c767a07fd9dab42a62b47410e0ba';

/// Local cover-file store (`<docs>/covers/<uuid>.jpg`) for captured covers.
///
/// Copied from [coverStore].
@ProviderFor(coverStore)
final coverStoreProvider = AutoDisposeFutureProvider<CoverStore>.internal(
  coverStore,
  name: r'coverStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$coverStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CoverStoreRef = AutoDisposeFutureProviderRef<CoverStore>;
String _$libraryLanguagesHash() => r'3a6110bd1c22af9da9324346134f6ff1342de7eb';

/// Distinct non-blank languages present in the library (filter-chip facets).
///
/// Copied from [libraryLanguages].
@ProviderFor(libraryLanguages)
final libraryLanguagesProvider =
    AutoDisposeFutureProvider<List<String>>.internal(
      libraryLanguages,
      name: r'libraryLanguagesProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$libraryLanguagesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LibraryLanguagesRef = AutoDisposeFutureProviderRef<List<String>>;
String _$addBookUseCaseHash() => r'5634f963c49d02ac7f830fcbfcc674d4abb5a929';

/// Adds a new book to the library (title-required validation + persist).
///
/// Copied from [addBookUseCase].
@ProviderFor(addBookUseCase)
final addBookUseCaseProvider =
    AutoDisposeFutureProvider<AddBookUseCase>.internal(
      addBookUseCase,
      name: r'addBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddBookUseCaseRef = AutoDisposeFutureProviderRef<AddBookUseCase>;
String _$updateBookUseCaseHash() => r'e92678950b1d2074408647f0f4d0ee91c165c658';

/// Updates an existing library book (title-required, id-immutable).
///
/// Copied from [updateBookUseCase].
@ProviderFor(updateBookUseCase)
final updateBookUseCaseProvider =
    AutoDisposeFutureProvider<UpdateBookUseCase>.internal(
      updateBookUseCase,
      name: r'updateBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$updateBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpdateBookUseCaseRef = AutoDisposeFutureProviderRef<UpdateBookUseCase>;
String _$deleteBookUseCaseHash() => r'a8ca4a1e2c2190947c23e5afeb3af5d5cfbc047a';

/// Hard-deletes a library book, purging its vault loans when unlocked (#27/D3).
/// The vault side is the session controller (it satisfies [VaultLoanPurger]).
///
/// Copied from [deleteBookUseCase].
@ProviderFor(deleteBookUseCase)
final deleteBookUseCaseProvider =
    AutoDisposeFutureProvider<DeleteBookUseCase>.internal(
      deleteBookUseCase,
      name: r'deleteBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$deleteBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeleteBookUseCaseRef = AutoDisposeFutureProviderRef<DeleteBookUseCase>;
String _$wishlistRepositoryHash() =>
    r'8e19c7be00a2d645e10c288df3ad187eb80a6bd2';

/// Wishlist repository.
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
String _$addWishlistBookUseCaseHash() =>
    r'f2939e19c468dda0f080dde738b6eab057cf9189';

/// Adds a new wishlist entry (title-required validation + persist).
///
/// Copied from [addWishlistBookUseCase].
@ProviderFor(addWishlistBookUseCase)
final addWishlistBookUseCaseProvider =
    AutoDisposeFutureProvider<AddWishlistBookUseCase>.internal(
      addWishlistBookUseCase,
      name: r'addWishlistBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addWishlistBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddWishlistBookUseCaseRef =
    AutoDisposeFutureProviderRef<AddWishlistBookUseCase>;
String _$updateWishlistBookUseCaseHash() =>
    r'859d07c24246f62b397e65fee672d0d856f1d2ed';

/// Updates a wishlist entry (title-required; id + addedDate immutable).
///
/// Copied from [updateWishlistBookUseCase].
@ProviderFor(updateWishlistBookUseCase)
final updateWishlistBookUseCaseProvider =
    AutoDisposeFutureProvider<UpdateWishlistBookUseCase>.internal(
      updateWishlistBookUseCase,
      name: r'updateWishlistBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$updateWishlistBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpdateWishlistBookUseCaseRef =
    AutoDisposeFutureProviderRef<UpdateWishlistBookUseCase>;
String _$deleteWishlistBookUseCaseHash() =>
    r'aad9b5b28f378b53ef46dbac5108a51f84b7a812';

/// Deletes a wishlist entry by id.
///
/// Copied from [deleteWishlistBookUseCase].
@ProviderFor(deleteWishlistBookUseCase)
final deleteWishlistBookUseCaseProvider =
    AutoDisposeFutureProvider<DeleteWishlistBookUseCase>.internal(
      deleteWishlistBookUseCase,
      name: r'deleteWishlistBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$deleteWishlistBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeleteWishlistBookUseCaseRef =
    AutoDisposeFutureProviderRef<DeleteWishlistBookUseCase>;
String _$markWishlistPurchasedUseCaseHash() =>
    r'0fc8961c3fc625da58d602a889db0342859af14f';

/// Marks a wishlist entry purchased, with optional move-to-library (D2 check).
///
/// Copied from [markWishlistPurchasedUseCase].
@ProviderFor(markWishlistPurchasedUseCase)
final markWishlistPurchasedUseCaseProvider =
    AutoDisposeFutureProvider<MarkWishlistPurchasedUseCase>.internal(
      markWishlistPurchasedUseCase,
      name: r'markWishlistPurchasedUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$markWishlistPurchasedUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MarkWishlistPurchasedUseCaseRef =
    AutoDisposeFutureProviderRef<MarkWishlistPurchasedUseCase>;
String _$vaultRepositoryHash() => r'b025103b5b7756e34aa2a4ae6253a41800894295';

/// Encrypted borrowers vault, read through the Rust FFI core.
///
/// Copied from [vaultRepository].
@ProviderFor(vaultRepository)
final vaultRepositoryProvider = AutoDisposeProvider<VaultRepository>.internal(
  vaultRepository,
  name: r'vaultRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$vaultRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VaultRepositoryRef = AutoDisposeProviderRef<VaultRepository>;
String _$httpClientHash() => r'ed4c948b2fa39b9289a939034474b5f5551ff3b4';

/// Shared HTTP client for ISBN lookups (#30). Closed when disposed.
///
/// Copied from [httpClient].
@ProviderFor(httpClient)
final httpClientProvider = Provider<http.Client>.internal(
  httpClient,
  name: r'httpClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$httpClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HttpClientRef = ProviderRef<http.Client>;
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
String _$isbnLookupServiceHash() => r'1175c5e03c88c13b632a42a797f5074556e9bc02';

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
String _$gitHubApiHash() => r'5baecc276f9c998db49e26fc2598557889b56e8c';

/// GitHub API client for publishing (device flow + git data). Shares the app
/// HTTP client.
///
/// Copied from [gitHubApi].
@ProviderFor(gitHubApi)
final gitHubApiProvider = AutoDisposeProvider<GitHubApi>.internal(
  gitHubApi,
  name: r'gitHubApiProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gitHubApiHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GitHubApiRef = AutoDisposeProviderRef<GitHubApi>;
String _$publishCredentialStoreHash() =>
    r'3b31461d16fbf56902e23d43430383b9d60baf70';

/// Encrypted-at-rest GitHub publish credentials (token + clientId + repo).
///
/// Copied from [publishCredentialStore].
@ProviderFor(publishCredentialStore)
final publishCredentialStoreProvider =
    Provider<PublishCredentialStore>.internal(
      publishCredentialStore,
      name: r'publishCredentialStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishCredentialStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishCredentialStoreRef = ProviderRef<PublishCredentialStore>;
String _$gitHubDeviceFlowHash() => r'9d418017e634cd6c7a97077b15007ebb437dd9da';

/// GitHub Device Flow runner (#32 auth).
///
/// Copied from [gitHubDeviceFlow].
@ProviderFor(gitHubDeviceFlow)
final gitHubDeviceFlowProvider = AutoDisposeProvider<GitHubDeviceFlow>.internal(
  gitHubDeviceFlow,
  name: r'gitHubDeviceFlowProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gitHubDeviceFlowHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GitHubDeviceFlowRef = AutoDisposeProviderRef<GitHubDeviceFlow>;
String _$publishCoverIdsHash() => r'3c5bcadbb45d7e23406191680df0ebe5e294b100';

/// Salted cover-path ids for publish (no internal-id leak, F-01).
///
/// Copied from [publishCoverIds].
@ProviderFor(publishCoverIds)
final publishCoverIdsProvider = AutoDisposeProvider<PublishCoverIds>.internal(
  publishCoverIds,
  name: r'publishCoverIdsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$publishCoverIdsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishCoverIdsRef = AutoDisposeProviderRef<PublishCoverIds>;
String _$publishManifestStoreHash() =>
    r'c2991bc3cdd50b2e4ba1ef7cd506955430206d3b';

/// File-backed incremental-publish manifest, rooted at the app docs dir.
///
/// Copied from [publishManifestStore].
@ProviderFor(publishManifestStore)
final publishManifestStoreProvider =
    AutoDisposeFutureProvider<FilePublishManifestStore>.internal(
      publishManifestStore,
      name: r'publishManifestStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishManifestStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishManifestStoreRef =
    AutoDisposeFutureProviderRef<FilePublishManifestStore>;
String _$screenSecurityHash() => r'e9cf5896b361c1d071b4ac76293d15cf98e29b89';

/// OS-level screen-capture protection toggle (Android FLAG_SECURE) for vault
/// PII screens (#34/F-12). A narrow platform channel; no-op off Android.
///
/// Copied from [screenSecurity].
@ProviderFor(screenSecurity)
final screenSecurityProvider = AutoDisposeProvider<ScreenSecurity>.internal(
  screenSecurity,
  name: r'screenSecurityProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$screenSecurityHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ScreenSecurityRef = AutoDisposeProviderRef<ScreenSecurity>;
String _$fileShareServiceHash() => r'4caa4196352d292bcbf88099f9a02fb2e0deb5ba';

/// Hands generated files (exports, backups) to the OS share sheet. Overridden
/// in widget tests with a fake to assert what would be shared.
///
/// Copied from [fileShareService].
@ProviderFor(fileShareService)
final fileShareServiceProvider = AutoDisposeProvider<FileShareService>.internal(
  fileShareService,
  name: r'fileShareServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$fileShareServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FileShareServiceRef = AutoDisposeProviderRef<FileShareService>;
String _$biometricAuthenticatorHash() =>
    r'd5fa245de9ed636bf6ca0b8b51902528625b5df5';

/// Biometric/device-credential gate for optional vault unlock (#34 B2). Only
/// gates release of the hardware-stored secret S; never sees the vault key.
///
/// Copied from [biometricAuthenticator].
@ProviderFor(biometricAuthenticator)
final biometricAuthenticatorProvider =
    AutoDisposeProvider<BiometricAuthenticator>.internal(
      biometricAuthenticator,
      name: r'biometricAuthenticatorProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$biometricAuthenticatorHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BiometricAuthenticatorRef =
    AutoDisposeProviderRef<BiometricAuthenticator>;
String _$biometricKeyStoreHash() => r'91258552dc1fce1f32f32a008f67b1ec0af0eaad';

/// Hardware-backed store (Keystore/Keychain) for the biometric secret S (#34
/// B2). S is the only thing persisted for biometric unlock; the passphrase is
/// never stored.
///
/// Copied from [biometricKeyStore].
@ProviderFor(biometricKeyStore)
final biometricKeyStoreProvider =
    AutoDisposeProvider<BiometricKeyStore>.internal(
      biometricKeyStore,
      name: r'biometricKeyStoreProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$biometricKeyStoreHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BiometricKeyStoreRef = AutoDisposeProviderRef<BiometricKeyStore>;
String _$vaultStoreHash() => r'6a58c80807af41f6738d4263ab3a19e1317b5c16';

/// At-rest store for the persistent on-device vault (DB path + wrapped-key
/// blob), rooted at the app documents dir (#26.2, Q-26b).
///
/// Copied from [vaultStore].
@ProviderFor(vaultStore)
final vaultStoreProvider = AutoDisposeFutureProvider<VaultStore>.internal(
  vaultStore,
  name: r'vaultStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$vaultStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VaultStoreRef = AutoDisposeFutureProviderRef<VaultStore>;
String _$activeLoanCountsHash() => r'05735954ea2db53f2ccf5efa5e3216e3cefa7a79';

/// Active-loan counts per book id when the vault is UNLOCKED, or null when
/// locked/uninitialized (availability is unknown without the decrypted loans).
/// The library list watches this to show the "Not available" badge (#26.4).
///
/// Copied from [activeLoanCounts].
@ProviderFor(activeLoanCounts)
final activeLoanCountsProvider = AutoDisposeProvider<Map<int, int>?>.internal(
  activeLoanCounts,
  name: r'activeLoanCountsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$activeLoanCountsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ActiveLoanCountsRef = AutoDisposeProviderRef<Map<int, int>?>;
String _$borrowerProfileHash() => r'64dd91226f28e204c8931b3f847fc9bf21c4ab76';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return).
///
/// Copied from [borrowerProfile].
@ProviderFor(borrowerProfile)
const borrowerProfileProvider = BorrowerProfileFamily();

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return).
///
/// Copied from [borrowerProfile].
class BorrowerProfileFamily extends Family<BorrowerProfile?> {
  /// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
  /// null when locked or the borrower is gone (#27a). Recomputes when the session
  /// changes (e.g. after a lend/return).
  ///
  /// Copied from [borrowerProfile].
  const BorrowerProfileFamily();

  /// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
  /// null when locked or the borrower is gone (#27a). Recomputes when the session
  /// changes (e.g. after a lend/return).
  ///
  /// Copied from [borrowerProfile].
  BorrowerProfileProvider call(int borrowerId) {
    return BorrowerProfileProvider(borrowerId);
  }

  @override
  BorrowerProfileProvider getProviderOverride(
    covariant BorrowerProfileProvider provider,
  ) {
    return call(provider.borrowerId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'borrowerProfileProvider';
}

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return).
///
/// Copied from [borrowerProfile].
class BorrowerProfileProvider extends AutoDisposeProvider<BorrowerProfile?> {
  /// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
  /// null when locked or the borrower is gone (#27a). Recomputes when the session
  /// changes (e.g. after a lend/return).
  ///
  /// Copied from [borrowerProfile].
  BorrowerProfileProvider(int borrowerId)
    : this._internal(
        (ref) => borrowerProfile(ref as BorrowerProfileRef, borrowerId),
        from: borrowerProfileProvider,
        name: r'borrowerProfileProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$borrowerProfileHash,
        dependencies: BorrowerProfileFamily._dependencies,
        allTransitiveDependencies:
            BorrowerProfileFamily._allTransitiveDependencies,
        borrowerId: borrowerId,
      );

  BorrowerProfileProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.borrowerId,
  }) : super.internal();

  final int borrowerId;

  @override
  Override overrideWith(
    BorrowerProfile? Function(BorrowerProfileRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: BorrowerProfileProvider._internal(
        (ref) => create(ref as BorrowerProfileRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        borrowerId: borrowerId,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<BorrowerProfile?> createElement() {
    return _BorrowerProfileProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is BorrowerProfileProvider && other.borrowerId == borrowerId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, borrowerId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin BorrowerProfileRef on AutoDisposeProviderRef<BorrowerProfile?> {
  /// The parameter `borrowerId` of this provider.
  int get borrowerId;
}

class _BorrowerProfileProviderElement
    extends AutoDisposeProviderElement<BorrowerProfile?>
    with BorrowerProfileRef {
  _BorrowerProfileProviderElement(super.provider);

  @override
  int get borrowerId => (origin as BorrowerProfileProvider).borrowerId;
}

String _$pendingSnapshotHash() => r'55dee101a2cc60a4f9fc80ff80cc2cc8992c8000';

/// The vault-gated pending/reminders snapshot (#27b): overdue + due-soon loans
/// (from the unlocked vault) and needs-metadata books (from the library), or
/// null when the vault is locked. Recomputes when either source changes.
///
/// Copied from [pendingSnapshot].
@ProviderFor(pendingSnapshot)
final pendingSnapshotProvider =
    AutoDisposeFutureProvider<PendingSnapshot?>.internal(
      pendingSnapshot,
      name: r'pendingSnapshotProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pendingSnapshotHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PendingSnapshotRef = AutoDisposeFutureProviderRef<PendingSnapshot?>;
String _$openVaultFromArchiveHash() =>
    r'7334e4b18b46429af479f790753432f8036db7d0';

/// Read-only opener that unlocks + reads a vault from a `.pitabak` archive
/// (writes nothing; stages the DB in a scratch dir under the app docs dir).
///
/// Copied from [openVaultFromArchive].
@ProviderFor(openVaultFromArchive)
final openVaultFromArchiveProvider =
    AutoDisposeFutureProvider<OpenVaultFromArchive>.internal(
      openVaultFromArchive,
      name: r'openVaultFromArchiveProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$openVaultFromArchiveHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OpenVaultFromArchiveRef =
    AutoDisposeFutureProviderRef<OpenVaultFromArchive>;
String _$libraryBundleReaderHash() =>
    r'01d5daf5718041b3cf2a5a919a6dec33b9cc9324';

/// Reads Pitaka bundle (.zip) archives into an import payload, writing any
/// bundled covers under `<appDocs>/covers`.
///
/// Copied from [libraryBundleReader].
@ProviderFor(libraryBundleReader)
final libraryBundleReaderProvider =
    AutoDisposeFutureProvider<LibraryBundleReader>.internal(
      libraryBundleReader,
      name: r'libraryBundleReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$libraryBundleReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LibraryBundleReaderRef =
    AutoDisposeFutureProviderRef<LibraryBundleReader>;
String _$importLibraryUseCaseHash() =>
    r'7b84c6eb03884f248819d8fa3903076c7aabd2a2';

/// One-shot library/wishlist import use case.
///
/// Copied from [importLibraryUseCase].
@ProviderFor(importLibraryUseCase)
final importLibraryUseCaseProvider =
    AutoDisposeFutureProvider<ImportLibraryUseCase>.internal(
      importLibraryUseCase,
      name: r'importLibraryUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$importLibraryUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ImportLibraryUseCaseRef =
    AutoDisposeFutureProviderRef<ImportLibraryUseCase>;
String _$exportLibraryUseCaseHash() =>
    r'394ba07b4ce6c110421ddf992e9d4599d11fe908';

/// One-shot library/wishlist export use case.
///
/// Copied from [exportLibraryUseCase].
@ProviderFor(exportLibraryUseCase)
final exportLibraryUseCaseProvider =
    AutoDisposeFutureProvider<ExportLibraryUseCase>.internal(
      exportLibraryUseCase,
      name: r'exportLibraryUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$exportLibraryUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ExportLibraryUseCaseRef =
    AutoDisposeFutureProviderRef<ExportLibraryUseCase>;
String _$mergeLibraryUseCaseHash() =>
    r'4fc770346e2bd2509b0472f938660e38f95635a5';

/// Multi-maintainer library merge use case (PLAN-merge.md): reconciles an
/// incoming Pitaka-JSON file with the local catalogue behind the library-ID
/// gate. Reuses the book repo + settings (for the ID gate / adoption).
///
/// Copied from [mergeLibraryUseCase].
@ProviderFor(mergeLibraryUseCase)
final mergeLibraryUseCaseProvider =
    AutoDisposeFutureProvider<MergeLibraryUseCase>.internal(
      mergeLibraryUseCase,
      name: r'mergeLibraryUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$mergeLibraryUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MergeLibraryUseCaseRef =
    AutoDisposeFutureProviderRef<MergeLibraryUseCase>;
String _$createBackupUseCaseHash() =>
    r'6dd381d8b5ef29bb19c9e55cf1ef6040050b9800';

/// Creates a `.pitabak` backup of the whole local catalog (#28B): Room-format
/// books/wishlist written from Drift, the persistent vault copied verbatim, and
/// covers bundled. Returns the archive bytes for the UI to save.
///
/// Copied from [createBackupUseCase].
@ProviderFor(createBackupUseCase)
final createBackupUseCaseProvider =
    AutoDisposeFutureProvider<CreateBackupUseCase>.internal(
      createBackupUseCase,
      name: r'createBackupUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$createBackupUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CreateBackupUseCaseRef =
    AutoDisposeFutureProviderRef<CreateBackupUseCase>;
String _$restoreBackupHash() => r'4921a0ced70a3d09145e4cdaeeb83605b1173e0e';

/// Backup-archive restorer (authoritative overwrite of local state).
///
/// Copied from [restoreBackup].
@ProviderFor(restoreBackup)
final restoreBackupProvider = AutoDisposeFutureProvider<RestoreBackup>.internal(
  restoreBackup,
  name: r'restoreBackupProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$restoreBackupHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RestoreBackupRef = AutoDisposeFutureProviderRef<RestoreBackup>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
