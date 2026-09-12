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
String _$dataGenerationsHash() => r'5c7eb39a9f63c79decce85093ed046e046d888ce';

/// Versioned data-generation store under `<appDocs>/data` (M02). The
/// catalogue DB, covers and vault live INSIDE the active generation so a
/// restore can build a complete new set and switch to it atomically.
///
/// Copied from [dataGenerations].
@ProviderFor(dataGenerations)
final dataGenerationsProvider = FutureProvider<DataGenerations>.internal(
  dataGenerations,
  name: r'dataGenerationsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$dataGenerationsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DataGenerationsRef = FutureProviderRef<DataGenerations>;
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
String _$coverStoreHash() => r'3e37265513e4d8f8ebe1cb6156feada810867fe2';

/// Local cover-file store (`<docs>/covers/<uuid>.jpg`) for captured covers,
/// exposed as the domain [CoverFiles] port.
///
/// Copied from [coverStore].
@ProviderFor(coverStore)
final coverStoreProvider = AutoDisposeFutureProvider<CoverFiles>.internal(
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
typedef CoverStoreRef = AutoDisposeFutureProviderRef<CoverFiles>;
String _$coverFileCoordinatorHash() =>
    r'5dcbe8a5922a3856e1451d69e042effaf2ce7e48';

/// Shared for the app lifetime: old/new auto-disposed callers must coordinate
/// on the same FIFO while an import or a cleanup operation is still running.
///
/// Copied from [coverFileCoordinator].
@ProviderFor(coverFileCoordinator)
final coverFileCoordinatorProvider = Provider<CoverFileCoordinator>.internal(
  coverFileCoordinator,
  name: r'coverFileCoordinatorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$coverFileCoordinatorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CoverFileCoordinatorRef = ProviderRef<CoverFileCoordinator>;
String _$coverFileJanitorHash() => r'84e84acfff56b9566de8f56654ed51b13214ef4f';

/// Removes cover files nothing references any more (decision Q12). Used right
/// after a cover/logo is replaced or a book hard-deleted, and once at startup
/// to sweep orphans left by older versions.
///
/// Copied from [coverFileJanitor].
@ProviderFor(coverFileJanitor)
final coverFileJanitorProvider =
    AutoDisposeFutureProvider<CoverFileJanitor>.internal(
      coverFileJanitor,
      name: r'coverFileJanitorProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$coverFileJanitorHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CoverFileJanitorRef = AutoDisposeFutureProviderRef<CoverFileJanitor>;
String _$orphanCoverSweepHash() => r'5629deddc4c1e50e48a2beeab575b6900ea01641';

/// One-shot startup sweep of orphan cover files; resolves to the number
/// removed. Triggered by the Library screen's first build (the composition
/// point that already owns the database), AFTER the list has loaded so the
/// sweep never competes with the first paint.
///
/// keepAlive: "once per app session" is the whole point — an autoDispose
/// provider would re-run the directory scan every time the screen rebuilt.
///
/// Copied from [orphanCoverSweep].
@ProviderFor(orphanCoverSweep)
final orphanCoverSweepProvider = FutureProvider<int>.internal(
  orphanCoverSweep,
  name: r'orphanCoverSweepProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$orphanCoverSweepHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OrphanCoverSweepRef = FutureProviderRef<int>;
String _$libraryLanguagesHash() => r'2a364532644d3ec8e92827900f72634de41b9c0b';

/// Distinct non-blank languages present in the library (filter-chip facets).
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [bookById]) — watching only the repository OBJECT never fires,
/// so without this an add/edit/import/restore left the chips stale.
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
String _$deleteBookUseCaseHash() => r'8bd4c759d1381fe6667a5baa01a7ff658f3301a0';

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
String _$lendBookUseCaseHash() => r'702f1ef9462049d97263029661828927bf72eb52';

/// Lends a library book, enforcing the lending policy (removed / all copies
/// out → refused with a reason). The vault side is the session controller
/// (it satisfies [VaultLender]).
///
/// Copied from [lendBookUseCase].
@ProviderFor(lendBookUseCase)
final lendBookUseCaseProvider =
    AutoDisposeFutureProvider<LendBookUseCase>.internal(
      lendBookUseCase,
      name: r'lendBookUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$lendBookUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LendBookUseCaseRef = AutoDisposeFutureProviderRef<LendBookUseCase>;
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
String _$httpClientHash() => r'648965b3207e4b12fb288ad3ef972854752613c6';

/// Shared HTTP client (#30, closes audit m1; N08). Every request through it
/// is bounded four ways and ABORTED (socket closed) when a bound trips, so a
/// dead socket (OEM app freezers, dropped mobile data), a trickling body or
/// an oversized reply fails closed instead of hanging or filling memory:
///  - 60 s to connect, 60 s between body chunks (per-phase `timeout`);
///  - 60 s for the whole request (`totalDeadline`; a body that sends one
///    byte every 59 s used to live forever);
///  - 64 MiB of body (`maxResponseBytes`, the default — sized to the largest
///    legitimate reply, a 100 000-row `books.json` read-back).
/// Closed when disposed.
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
String _$lookupHttpClientHash() => r'b3c4ea0272408aceb7afd2c145148c0243ba1d72';

/// HTTP client for the public book-metadata APIs only. Differs from the
/// shared [httpClient] in two ways (REVIEW: lookup — "fails quite often"):
///  - 10 s per phase and 30 s total, not 60: lookups are interactive (user
///    watching a spinner); a slow provider should fail over to the fallback
///    quickly, not pin the button for a minute. 30 s total is 3× the phase
///    limit so a healthy-but-slow JSON reply still completes (N08, D1).
///  - [LookupHttpClient] on top: descriptive User-Agent (Open Library's API
///    policy throttles anonymous clients) + one jittered retry on 429/5xx.
///
/// Copied from [lookupHttpClient].
@ProviderFor(lookupHttpClient)
final lookupHttpClientProvider = Provider<http.Client>.internal(
  lookupHttpClient,
  name: r'lookupHttpClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$lookupHttpClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LookupHttpClientRef = ProviderRef<http.Client>;
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
String _$setupGitHubRepoHash() => r'9281c5b0bdaf50685d0cdf621a85cf7445784933';

/// One-tap repo setup: create/adopt the publish repo + enable Pages
/// (mirrors Localcart Orange's github_setup).
///
/// Copied from [setupGitHubRepo].
@ProviderFor(setupGitHubRepo)
final setupGitHubRepoProvider = AutoDisposeProvider<SetupGitHubRepo>.internal(
  setupGitHubRepo,
  name: r'setupGitHubRepoProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$setupGitHubRepoHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SetupGitHubRepoRef = AutoDisposeProviderRef<SetupGitHubRepo>;
String _$boundedCoverDownloadHash() =>
    r'01522357ad2ef65c99f4950654c67474aa1c094e';

/// Bounded, typed remote-cover download (M1: allow-list + deadline + byte
/// cap; N08: the deadline aborts the socket) with the publish downscale
/// applied. THE single implementation both the publish path and the M09
/// on-device materialisation use, so the display path can never fetch
/// anything publish would refuse. Returns the publish-domain
/// [CoverFetchResult] so the caller can tell WHY a cover was refused.
///
/// Copied from [boundedCoverDownload].
@ProviderFor(boundedCoverDownload)
final boundedCoverDownloadProvider =
    AutoDisposeProvider<BoundedCoverDownload>.internal(
      boundedCoverDownload,
      name: r'boundedCoverDownloadProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$boundedCoverDownloadHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BoundedCoverDownloadRef = AutoDisposeProviderRef<BoundedCoverDownload>;
String _$remoteCoverFetcherHash() =>
    r'742d985f4f48dcb51857da1b934c748cd33799d6';

/// Publish-side view of [boundedCoverDownload]: bytes or null. Injected into
/// the publish controller as a domain function type so the application layer
/// never constructs the HTTP-backed fetcher itself (§3.1). Publish only needs
/// "did we get a cover"; the refusal reason is a display-path diagnostic.
///
/// Copied from [remoteCoverFetcher].
@ProviderFor(remoteCoverFetcher)
final remoteCoverFetcherProvider =
    AutoDisposeProvider<RemoteCoverFetcher>.internal(
      remoteCoverFetcher,
      name: r'remoteCoverFetcherProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$remoteCoverFetcherHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef RemoteCoverFetcherRef = AutoDisposeProviderRef<RemoteCoverFetcher>;
String _$materializeRemoteCoverUseCaseHash() =>
    r'b734d46f7ab9ab5d4c25d8746023e1bd9bafabf9';

/// Materialises a book's allow-listed remote cover as a local file (M09),
/// through the same bounded download publishing uses and the same cover store
/// / janitor a photo replace uses.
///
/// N11 D4-b: a refused download is reported here as ONE debug-build log line
/// carrying the book id and the coarse [CoverRefusal] — never the URL or host
/// (AGENTS.md §6.2). `kDebugMode` makes it a no-op in release builds; no
/// telemetry (§3.4). The composition root owns the Flutter import so the
/// application layer stays framework-free.
///
/// Copied from [materializeRemoteCoverUseCase].
@ProviderFor(materializeRemoteCoverUseCase)
final materializeRemoteCoverUseCaseProvider =
    AutoDisposeFutureProvider<MaterializeRemoteCoverUseCase>.internal(
      materializeRemoteCoverUseCase,
      name: r'materializeRemoteCoverUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$materializeRemoteCoverUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MaterializeRemoteCoverUseCaseRef =
    AutoDisposeFutureProviderRef<MaterializeRemoteCoverUseCase>;
String _$publishLocalCoverReaderHash() =>
    r'e4afffa4a1e4a55a6150cb829b6618cf9705b70f';

/// Local cover-file reader for publishing (N14): the file IO the publish
/// controller used to do itself (dart:io in the application layer). Injected
/// as a function port, rooted at the app's covers directory.
///
/// Copied from [publishLocalCoverReader].
@ProviderFor(publishLocalCoverReader)
final publishLocalCoverReaderProvider =
    AutoDisposeFutureProvider<Future<List<int>?> Function(String)>.internal(
      publishLocalCoverReader,
      name: r'publishLocalCoverReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishLocalCoverReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishLocalCoverReaderRef =
    AutoDisposeFutureProviderRef<Future<List<int>?> Function(String)>;
String _$publishedFileFetcherHash() =>
    r'2e06db835520facdf9a4b173f72cea48e65d2ef4';

/// Published-file fetcher for the post-publish read-back (à la Localcart
/// Orange): plain GET of a PUBLIC Pages URL — no auth, no token. Null on any
/// failure; the read-back treats that as "not visible yet".
///
/// Copied from [publishedFileFetcher].
@ProviderFor(publishedFileFetcher)
final publishedFileFetcherProvider =
    AutoDisposeProvider<PublishedFileFetcher>.internal(
      publishedFileFetcher,
      name: r'publishedFileFetcherProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$publishedFileFetcherHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedFileFetcherRef = AutoDisposeProviderRef<PublishedFileFetcher>;
String _$viewerHtmlFactoryHash() => r'341b7961fe4a972e730e7da176011335efce9112';

/// Viewer-HTML factory port: loads the bundled template (rootBundle — a side
/// effect, so it lives behind this seam) and substitutes the library values.
///
/// Copied from [viewerHtmlFactory].
@ProviderFor(viewerHtmlFactory)
final viewerHtmlFactoryProvider =
    AutoDisposeProvider<ViewerHtmlFactory>.internal(
      viewerHtmlFactory,
      name: r'viewerHtmlFactoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$viewerHtmlFactoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ViewerHtmlFactoryRef = AutoDisposeProviderRef<ViewerHtmlFactory>;
String _$eventsHtmlFactoryHash() => r'7058a3a71f60555a5519580a6179123a19ade047';

/// Events-HTML factory port: same seam as [viewerHtmlFactory] for the events
/// page template.
///
/// Copied from [eventsHtmlFactory].
@ProviderFor(eventsHtmlFactory)
final eventsHtmlFactoryProvider =
    AutoDisposeProvider<EventsHtmlFactory>.internal(
      eventsHtmlFactory,
      name: r'eventsHtmlFactoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$eventsHtmlFactoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsHtmlFactoryRef = AutoDisposeProviderRef<EventsHtmlFactory>;
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
    r'5aa1156d243efd66c3ce996c2ee810a597c87928';

/// File-backed incremental-publish manifest, rooted at the app docs dir.
/// Expose the port so tests can substitute an in-memory store without file IO.
///
/// Copied from [publishManifestStore].
@ProviderFor(publishManifestStore)
final publishManifestStoreProvider =
    AutoDisposeFutureProvider<PublishManifestGateway>.internal(
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
    AutoDisposeFutureProviderRef<PublishManifestGateway>;
String _$publishedSiteUrlHash() => r'b1c5668f3b27c7f3570b9d5cf877fac1410f06c7';

/// The live URL of the user's published library site, or null when nothing
/// has been published yet. Derived from the publish manifest's `repo` field,
/// which is only written AFTER a successful publish — so this is null for a
/// repo that was created but never published. Public data (the URL is the
/// whole point); no secrets involved.
///
/// Copied from [publishedSiteUrl].
@ProviderFor(publishedSiteUrl)
final publishedSiteUrlProvider = AutoDisposeFutureProvider<String?>.internal(
  publishedSiteUrl,
  name: r'publishedSiteUrlProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$publishedSiteUrlHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PublishedSiteUrlRef = AutoDisposeFutureProviderRef<String?>;
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
String _$screenCaptureProtectedHash() =>
    r'4270b86c7cebaa1556cb10261ebed6aa92ad0c57';

/// Single source of truth for the window FLAG_SECURE policy: ON when the
/// vault is unlocked (borrower PII visible) OR any passphrase entry field is
/// visible (#34/F-12 + REVIEW_FINDINGS_2 S2). main.dart listens to this and
/// drives [screenSecurityProvider] — one decision point, so the page-level
/// and vault-level signals can never race each other.
///
/// Copied from [screenCaptureProtected].
@ProviderFor(screenCaptureProtected)
final screenCaptureProtectedProvider = AutoDisposeProvider<bool>.internal(
  screenCaptureProtected,
  name: r'screenCaptureProtectedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$screenCaptureProtectedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ScreenCaptureProtectedRef = AutoDisposeProviderRef<bool>;
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
String _$biometricKeyStoreHash() => r'532530e30abc69378861ee9b82b2b900c2e97ade';

/// Sealed, authentication-bound store for the biometric secret S (#34 B2,
/// M08). S is the only thing persisted for biometric unlock; the passphrase is
/// never stored. On Android the store encrypts S under a Keystore key that
/// requires a fresh strong-biometric authentication per use; on any platform
/// without the native handler it fails closed ("not available").
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
String _$vaultStoreHash() => r'022b6a19c0e5283e4b96d54f14892995881cf96e';

/// At-rest store for the persistent on-device vault (DB path + wrapped-key
/// blob), rooted inside the active data generation (M02; was the app documents
/// dir before, #26.2, Q-26b).
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
String _$bookTitleHash() => r'28364f805a0d70587da0bc12c5972ee98c3ec4f5';

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

/// Loan-row read model (N06): resolves the catalogue title of a loaned book
/// so borrower screens show the book's name instead of the internal row id.
/// Null when the book no longer exists (the UI falls back to "Book #id").
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [bookById]) so a rename reaches open borrower screens.
///
/// Copied from [bookTitle].
@ProviderFor(bookTitle)
const bookTitleProvider = BookTitleFamily();

/// Loan-row read model (N06): resolves the catalogue title of a loaned book
/// so borrower screens show the book's name instead of the internal row id.
/// Null when the book no longer exists (the UI falls back to "Book #id").
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [bookById]) so a rename reaches open borrower screens.
///
/// Copied from [bookTitle].
class BookTitleFamily extends Family<AsyncValue<String?>> {
  /// Loan-row read model (N06): resolves the catalogue title of a loaned book
  /// so borrower screens show the book's name instead of the internal row id.
  /// Null when the book no longer exists (the UI falls back to "Book #id").
  ///
  /// N04: watches [libraryControllerProvider] as the mutation signal (same
  /// pattern as [bookById]) so a rename reaches open borrower screens.
  ///
  /// Copied from [bookTitle].
  const BookTitleFamily();

  /// Loan-row read model (N06): resolves the catalogue title of a loaned book
  /// so borrower screens show the book's name instead of the internal row id.
  /// Null when the book no longer exists (the UI falls back to "Book #id").
  ///
  /// N04: watches [libraryControllerProvider] as the mutation signal (same
  /// pattern as [bookById]) so a rename reaches open borrower screens.
  ///
  /// Copied from [bookTitle].
  BookTitleProvider call({required int bookId}) {
    return BookTitleProvider(bookId: bookId);
  }

  @override
  BookTitleProvider getProviderOverride(covariant BookTitleProvider provider) {
    return call(bookId: provider.bookId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'bookTitleProvider';
}

/// Loan-row read model (N06): resolves the catalogue title of a loaned book
/// so borrower screens show the book's name instead of the internal row id.
/// Null when the book no longer exists (the UI falls back to "Book #id").
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [bookById]) so a rename reaches open borrower screens.
///
/// Copied from [bookTitle].
class BookTitleProvider extends AutoDisposeFutureProvider<String?> {
  /// Loan-row read model (N06): resolves the catalogue title of a loaned book
  /// so borrower screens show the book's name instead of the internal row id.
  /// Null when the book no longer exists (the UI falls back to "Book #id").
  ///
  /// N04: watches [libraryControllerProvider] as the mutation signal (same
  /// pattern as [bookById]) so a rename reaches open borrower screens.
  ///
  /// Copied from [bookTitle].
  BookTitleProvider({required int bookId})
    : this._internal(
        (ref) => bookTitle(ref as BookTitleRef, bookId: bookId),
        from: bookTitleProvider,
        name: r'bookTitleProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$bookTitleHash,
        dependencies: BookTitleFamily._dependencies,
        allTransitiveDependencies: BookTitleFamily._allTransitiveDependencies,
        bookId: bookId,
      );

  BookTitleProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.bookId,
  }) : super.internal();

  final int bookId;

  @override
  Override overrideWith(
    FutureOr<String?> Function(BookTitleRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: BookTitleProvider._internal(
        (ref) => create(ref as BookTitleRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        bookId: bookId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<String?> createElement() {
    return _BookTitleProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is BookTitleProvider && other.bookId == bookId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, bookId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin BookTitleRef on AutoDisposeFutureProviderRef<String?> {
  /// The parameter `bookId` of this provider.
  int get bookId;
}

class _BookTitleProviderElement
    extends AutoDisposeFutureProviderElement<String?>
    with BookTitleRef {
  _BookTitleProviderElement(super.provider);

  @override
  int get bookId => (origin as BookTitleProvider).bookId;
}

String _$bookByIdHash() => r'f7ac65edbecd807956445160bedf1cfac802390d';

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `Book` the list row was tapped with: a detail
/// page can stay open while the row changes underneath it — a cover captured
/// on that very page rewrites `coverUrl`, the remote-cover materializer may
/// swap an `https://` reference for a local file, an edit saves new fields.
/// A snapshot handed in at push time never learns any of this, and passing it
/// on to the edit form wrote stale values back over the fresh row (a cover
/// file the janitor had already deleted came back as the row's cover).
///
/// Freshness signal: every mutation path in the app already invalidates or
/// refreshes [libraryControllerProvider] (cover replace, materializer, edit
/// save, remove/restore, import, restore, wishlist move). Watching it here —
/// value ignored — makes this provider re-read the row on the same signal,
/// with no new plumbing. The repository has no row streams (N04); when it
/// gains one this dependency is the single line to swap.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError` (same idiom as `LibraryController._load`).
///
/// Copied from [bookById].
@ProviderFor(bookById)
const bookByIdProvider = BookByIdFamily();

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `Book` the list row was tapped with: a detail
/// page can stay open while the row changes underneath it — a cover captured
/// on that very page rewrites `coverUrl`, the remote-cover materializer may
/// swap an `https://` reference for a local file, an edit saves new fields.
/// A snapshot handed in at push time never learns any of this, and passing it
/// on to the edit form wrote stale values back over the fresh row (a cover
/// file the janitor had already deleted came back as the row's cover).
///
/// Freshness signal: every mutation path in the app already invalidates or
/// refreshes [libraryControllerProvider] (cover replace, materializer, edit
/// save, remove/restore, import, restore, wishlist move). Watching it here —
/// value ignored — makes this provider re-read the row on the same signal,
/// with no new plumbing. The repository has no row streams (N04); when it
/// gains one this dependency is the single line to swap.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError` (same idiom as `LibraryController._load`).
///
/// Copied from [bookById].
class BookByIdFamily extends Family<AsyncValue<Book?>> {
  /// One library book, observed by id, for a detail screen (N03).
  ///
  /// Why a provider and not the `Book` the list row was tapped with: a detail
  /// page can stay open while the row changes underneath it — a cover captured
  /// on that very page rewrites `coverUrl`, the remote-cover materializer may
  /// swap an `https://` reference for a local file, an edit saves new fields.
  /// A snapshot handed in at push time never learns any of this, and passing it
  /// on to the edit form wrote stale values back over the fresh row (a cover
  /// file the janitor had already deleted came back as the row's cover).
  ///
  /// Freshness signal: every mutation path in the app already invalidates or
  /// refreshes [libraryControllerProvider] (cover replace, materializer, edit
  /// save, remove/restore, import, restore, wishlist move). Watching it here —
  /// value ignored — makes this provider re-read the row on the same signal,
  /// with no new plumbing. The repository has no row streams (N04); when it
  /// gains one this dependency is the single line to swap.
  ///
  /// `null` = the row no longer exists. A repository `Left` is thrown so the
  /// screen sees `AsyncError` (same idiom as `LibraryController._load`).
  ///
  /// Copied from [bookById].
  const BookByIdFamily();

  /// One library book, observed by id, for a detail screen (N03).
  ///
  /// Why a provider and not the `Book` the list row was tapped with: a detail
  /// page can stay open while the row changes underneath it — a cover captured
  /// on that very page rewrites `coverUrl`, the remote-cover materializer may
  /// swap an `https://` reference for a local file, an edit saves new fields.
  /// A snapshot handed in at push time never learns any of this, and passing it
  /// on to the edit form wrote stale values back over the fresh row (a cover
  /// file the janitor had already deleted came back as the row's cover).
  ///
  /// Freshness signal: every mutation path in the app already invalidates or
  /// refreshes [libraryControllerProvider] (cover replace, materializer, edit
  /// save, remove/restore, import, restore, wishlist move). Watching it here —
  /// value ignored — makes this provider re-read the row on the same signal,
  /// with no new plumbing. The repository has no row streams (N04); when it
  /// gains one this dependency is the single line to swap.
  ///
  /// `null` = the row no longer exists. A repository `Left` is thrown so the
  /// screen sees `AsyncError` (same idiom as `LibraryController._load`).
  ///
  /// Copied from [bookById].
  BookByIdProvider call(int bookId) {
    return BookByIdProvider(bookId);
  }

  @override
  BookByIdProvider getProviderOverride(covariant BookByIdProvider provider) {
    return call(provider.bookId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'bookByIdProvider';
}

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `Book` the list row was tapped with: a detail
/// page can stay open while the row changes underneath it — a cover captured
/// on that very page rewrites `coverUrl`, the remote-cover materializer may
/// swap an `https://` reference for a local file, an edit saves new fields.
/// A snapshot handed in at push time never learns any of this, and passing it
/// on to the edit form wrote stale values back over the fresh row (a cover
/// file the janitor had already deleted came back as the row's cover).
///
/// Freshness signal: every mutation path in the app already invalidates or
/// refreshes [libraryControllerProvider] (cover replace, materializer, edit
/// save, remove/restore, import, restore, wishlist move). Watching it here —
/// value ignored — makes this provider re-read the row on the same signal,
/// with no new plumbing. The repository has no row streams (N04); when it
/// gains one this dependency is the single line to swap.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError` (same idiom as `LibraryController._load`).
///
/// Copied from [bookById].
class BookByIdProvider extends AutoDisposeFutureProvider<Book?> {
  /// One library book, observed by id, for a detail screen (N03).
  ///
  /// Why a provider and not the `Book` the list row was tapped with: a detail
  /// page can stay open while the row changes underneath it — a cover captured
  /// on that very page rewrites `coverUrl`, the remote-cover materializer may
  /// swap an `https://` reference for a local file, an edit saves new fields.
  /// A snapshot handed in at push time never learns any of this, and passing it
  /// on to the edit form wrote stale values back over the fresh row (a cover
  /// file the janitor had already deleted came back as the row's cover).
  ///
  /// Freshness signal: every mutation path in the app already invalidates or
  /// refreshes [libraryControllerProvider] (cover replace, materializer, edit
  /// save, remove/restore, import, restore, wishlist move). Watching it here —
  /// value ignored — makes this provider re-read the row on the same signal,
  /// with no new plumbing. The repository has no row streams (N04); when it
  /// gains one this dependency is the single line to swap.
  ///
  /// `null` = the row no longer exists. A repository `Left` is thrown so the
  /// screen sees `AsyncError` (same idiom as `LibraryController._load`).
  ///
  /// Copied from [bookById].
  BookByIdProvider(int bookId)
    : this._internal(
        (ref) => bookById(ref as BookByIdRef, bookId),
        from: bookByIdProvider,
        name: r'bookByIdProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$bookByIdHash,
        dependencies: BookByIdFamily._dependencies,
        allTransitiveDependencies: BookByIdFamily._allTransitiveDependencies,
        bookId: bookId,
      );

  BookByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.bookId,
  }) : super.internal();

  final int bookId;

  @override
  Override overrideWith(FutureOr<Book?> Function(BookByIdRef provider) create) {
    return ProviderOverride(
      origin: this,
      override: BookByIdProvider._internal(
        (ref) => create(ref as BookByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        bookId: bookId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Book?> createElement() {
    return _BookByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is BookByIdProvider && other.bookId == bookId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, bookId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin BookByIdRef on AutoDisposeFutureProviderRef<Book?> {
  /// The parameter `bookId` of this provider.
  int get bookId;
}

class _BookByIdProviderElement extends AutoDisposeFutureProviderElement<Book?>
    with BookByIdRef {
  _BookByIdProviderElement(super.provider);

  @override
  int get bookId => (origin as BookByIdProvider).bookId;
}

String _$wishlistBookByIdHash() => r'176febc233f1cf5a199182f23de5b012c91873dd';

/// One wishlist entry, observed by id, for its detail screen (N03).
/// Same shape and rationale as [bookById]; the freshness signal is
/// [wishlistControllerProvider], which every wishlist mutation refreshes.
///
/// Copied from [wishlistBookById].
@ProviderFor(wishlistBookById)
const wishlistBookByIdProvider = WishlistBookByIdFamily();

/// One wishlist entry, observed by id, for its detail screen (N03).
/// Same shape and rationale as [bookById]; the freshness signal is
/// [wishlistControllerProvider], which every wishlist mutation refreshes.
///
/// Copied from [wishlistBookById].
class WishlistBookByIdFamily extends Family<AsyncValue<WishlistBook?>> {
  /// One wishlist entry, observed by id, for its detail screen (N03).
  /// Same shape and rationale as [bookById]; the freshness signal is
  /// [wishlistControllerProvider], which every wishlist mutation refreshes.
  ///
  /// Copied from [wishlistBookById].
  const WishlistBookByIdFamily();

  /// One wishlist entry, observed by id, for its detail screen (N03).
  /// Same shape and rationale as [bookById]; the freshness signal is
  /// [wishlistControllerProvider], which every wishlist mutation refreshes.
  ///
  /// Copied from [wishlistBookById].
  WishlistBookByIdProvider call(int bookId) {
    return WishlistBookByIdProvider(bookId);
  }

  @override
  WishlistBookByIdProvider getProviderOverride(
    covariant WishlistBookByIdProvider provider,
  ) {
    return call(provider.bookId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'wishlistBookByIdProvider';
}

/// One wishlist entry, observed by id, for its detail screen (N03).
/// Same shape and rationale as [bookById]; the freshness signal is
/// [wishlistControllerProvider], which every wishlist mutation refreshes.
///
/// Copied from [wishlistBookById].
class WishlistBookByIdProvider
    extends AutoDisposeFutureProvider<WishlistBook?> {
  /// One wishlist entry, observed by id, for its detail screen (N03).
  /// Same shape and rationale as [bookById]; the freshness signal is
  /// [wishlistControllerProvider], which every wishlist mutation refreshes.
  ///
  /// Copied from [wishlistBookById].
  WishlistBookByIdProvider(int bookId)
    : this._internal(
        (ref) => wishlistBookById(ref as WishlistBookByIdRef, bookId),
        from: wishlistBookByIdProvider,
        name: r'wishlistBookByIdProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$wishlistBookByIdHash,
        dependencies: WishlistBookByIdFamily._dependencies,
        allTransitiveDependencies:
            WishlistBookByIdFamily._allTransitiveDependencies,
        bookId: bookId,
      );

  WishlistBookByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.bookId,
  }) : super.internal();

  final int bookId;

  @override
  Override overrideWith(
    FutureOr<WishlistBook?> Function(WishlistBookByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: WishlistBookByIdProvider._internal(
        (ref) => create(ref as WishlistBookByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        bookId: bookId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<WishlistBook?> createElement() {
    return _WishlistBookByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is WishlistBookByIdProvider && other.bookId == bookId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, bookId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin WishlistBookByIdRef on AutoDisposeFutureProviderRef<WishlistBook?> {
  /// The parameter `bookId` of this provider.
  int get bookId;
}

class _WishlistBookByIdProviderElement
    extends AutoDisposeFutureProviderElement<WishlistBook?>
    with WishlistBookByIdRef {
  _WishlistBookByIdProviderElement(super.provider);

  @override
  int get bookId => (origin as WishlistBookByIdProvider).bookId;
}

String _$clockHash() => r'95c05edbf47d123a7fa7805bf8535316be77b11c';

/// The wall clock as epoch milliseconds, behind a provider so tests can
/// inject a fake (N04). Same idiom as the `int Function()? clock` constructor
/// parameters in the lookup/publish use cases.
///
/// Copied from [clock].
@ProviderFor(clock)
final clockProvider = AutoDisposeProvider<int Function()>.internal(
  clock,
  name: r'clockProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$clockHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ClockRef = AutoDisposeProviderRef<int Function()>;
String _$nowTickHash() => r'819f71fe0a55e4c93a2f1358cfdc86fcc4381476';

/// Periodic "time has passed" signal (N04), watched by providers and widgets
/// whose output depends on the wall clock (overdue badges, due-soon reminders,
/// borrower stats) so a screen left open rolls over — a loan due at 15:00
/// turns overdue at 15:00, not at the next app start.
///
/// The value is the current epoch millis (NOT a constant event): Riverpod
/// only rebuilds dependents when the watched value changes, so a
/// `Stream.periodic` of identical events would never propagate. A self-
/// invalidating timer reschedules itself after every rebuild.
///
/// AutoDispose on purpose: the timer only runs while a screen is actually
/// watching, and `onDispose` cancels it (a pending timer would otherwise
/// outlive widget tests). Tests drive the same rebuild path by overriding
/// [clockProvider] and invalidating this provider instead of waiting out the
/// interval.
///
/// Copied from [nowTick].
@ProviderFor(nowTick)
final nowTickProvider = AutoDisposeProvider<int>.internal(
  nowTick,
  name: r'nowTickProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nowTickHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NowTickRef = AutoDisposeProviderRef<int>;
String _$borrowerProfileHash() => r'd2f99e338c068933632d302d21559f0b5816873e';

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
/// fires, so overdue stats roll over while the page stays open (N04).
///
/// Copied from [borrowerProfile].
@ProviderFor(borrowerProfile)
const borrowerProfileProvider = BorrowerProfileFamily();

/// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
/// null when locked or the borrower is gone (#27a). Recomputes when the session
/// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
/// fires, so overdue stats roll over while the page stays open (N04).
///
/// Copied from [borrowerProfile].
class BorrowerProfileFamily extends Family<BorrowerProfile?> {
  /// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
  /// null when locked or the borrower is gone (#27a). Recomputes when the session
  /// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
  /// fires, so overdue stats roll over while the page stays open (N04).
  ///
  /// Copied from [borrowerProfile].
  const BorrowerProfileFamily();

  /// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
  /// null when locked or the borrower is gone (#27a). Recomputes when the session
  /// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
  /// fires, so overdue stats roll over while the page stays open (N04).
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
/// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
/// fires, so overdue stats roll over while the page stays open (N04).
///
/// Copied from [borrowerProfile].
class BorrowerProfileProvider extends AutoDisposeProvider<BorrowerProfile?> {
  /// Builds the [BorrowerProfile] for [borrowerId] from the unlocked vault, or
  /// null when locked or the borrower is gone (#27a). Recomputes when the session
  /// changes (e.g. after a lend/return) and when the [nowTickProvider] tick
  /// fires, so overdue stats roll over while the page stays open (N04).
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

String _$pendingSnapshotHash() => r'49a6e23baf531178e17b9f6f78a12fa400007c62';

/// The vault-gated pending/reminders snapshot (#27b): overdue + due-soon loans
/// (from the unlocked vault) and needs-metadata books (from the library), or
/// null when the vault is locked. Recomputes when either source changes.
///
/// N04: watches [libraryControllerProvider] as the catalogue mutation signal
/// (same pattern as [bookById]) — watching only the repository OBJECT never
/// fired, so a needs-metadata edit, import or restore left the reminders
/// stale — and the [nowTickProvider] tick, so overdue/due-soon buckets roll
/// over while the screen stays open.
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
    r'9b5a65c16881ce1118e34d43334eae4ed427ceee';

/// Side-effect-free bundle decoding, exposed through its domain contract.
///
/// Copied from [libraryBundleReader].
@ProviderFor(libraryBundleReader)
final libraryBundleReaderProvider =
    AutoDisposeFutureProvider<BundleReader>.internal(
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
typedef LibraryBundleReaderRef = AutoDisposeFutureProviderRef<BundleReader>;
String _$bundleCoverFilesHash() => r'1a39d026e0238b00f8061007a6005f7afa808372';

/// Operation-owned imported covers under the existing app-private covers dir.
///
/// Copied from [bundleCoverFiles].
@ProviderFor(bundleCoverFiles)
final bundleCoverFilesProvider =
    AutoDisposeFutureProvider<BundleCoverFiles>.internal(
      bundleCoverFiles,
      name: r'bundleCoverFilesProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$bundleCoverFilesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BundleCoverFilesRef = AutoDisposeFutureProviderRef<BundleCoverFiles>;
String _$importLibraryUseCaseHash() =>
    r'30ac257e30c36a352ce4ff67e895c819020133a2';

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
String _$exportLogoReaderHash() => r'a98726e103d90ec921020da91e345d46495304d5';

/// Library-logo file reader for exports (N14): file IO injected as a port;
/// the application controller no longer touches dart:io.
///
/// Copied from [exportLogoReader].
@ProviderFor(exportLogoReader)
final exportLogoReaderProvider =
    AutoDisposeFutureProvider<Future<Uint8List?> Function(String)>.internal(
      exportLogoReader,
      name: r'exportLogoReaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$exportLogoReaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ExportLogoReaderRef =
    AutoDisposeFutureProviderRef<Future<Uint8List?> Function(String)>;
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
String _$exportLibraryUseCaseHash() =>
    r'efe6913015990d9cd6a03e40e1b26de914f4e14e';

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
String _$pdfFooterIconLoaderHash() =>
    r'49130e3985bd03424e7f5bc9b78322d3152c2e76';

/// Loads the bundled footer icon for the PDF export, or null when the asset
/// is missing (a missing icon must never block an export). Behind a provider
/// because `rootBundle` is a side effect the application layer must not own.
///
/// Copied from [pdfFooterIconLoader].
@ProviderFor(pdfFooterIconLoader)
final pdfFooterIconLoaderProvider =
    AutoDisposeProvider<Future<Uint8List?> Function()>.internal(
      pdfFooterIconLoader,
      name: r'pdfFooterIconLoaderProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pdfFooterIconLoaderHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PdfFooterIconLoaderRef =
    AutoDisposeProviderRef<Future<Uint8List?> Function()>;
String _$pdfTextRasterizerHash() => r'841e6d7a430d6ead5467b94ed731527f70f5ef44';

/// Shaped-text rasterizer for the PDF export (needs a live Flutter engine +
/// the bundled Noto fonts — infrastructure, injected as the domain
/// `PdfTextRasterizer` port).
///
/// Copied from [pdfTextRasterizer].
@ProviderFor(pdfTextRasterizer)
final pdfTextRasterizerProvider =
    AutoDisposeProvider<PdfTextRasterizer>.internal(
      pdfTextRasterizer,
      name: r'pdfTextRasterizerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$pdfTextRasterizerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PdfTextRasterizerRef = AutoDisposeProviderRef<PdfTextRasterizer>;
String _$mergeLibraryUseCaseHash() =>
    r'25091255548aad2ede63bdf161788c05ed2e2b12';

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
    r'26c2970f397dd08822a1616b02b7c30547572b51';

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
String _$restoreBackupHash() => r'8d7aa949f4ca117a64bafc962132974dc72c3d08';

/// Backup-archive restorer (authoritative overwrite of local state).
///
/// M02: restore builds a NEW data generation and switches to it atomically
/// through [ActiveDataGeneration.activate], which republishes the paths so the
/// database, covers and vault-store providers all rebuild onto the new set.
/// The active generation is resolved lazily (`ref.read` at call time), not
/// watched: watching would rebuild this restorer mid-switch for no benefit.
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
String _$eventsRepositoryHash() => r'fcff3cd04659820293505f831d60dde0d4a48e64';

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
String _$passphraseEntryVisibilityHash() =>
    r'cf6a246b57a5b9acf1fafc361cee75a0f3730746';

/// Count of currently-visible passphrase entry fields (vault create / unlock
/// / change-passphrase / restore flows). Incremented by
/// `SecurePassphraseField.initState`, decremented on dispose.
///
/// keepAlive is deliberate: the field captures this notifier in initState and
/// calls it again from dispose(), which is only safe if the notifier can
/// never be auto-disposed out from under the widget.
///
/// Copied from [PassphraseEntryVisibility].
@ProviderFor(PassphraseEntryVisibility)
final passphraseEntryVisibilityProvider =
    NotifierProvider<PassphraseEntryVisibility, int>.internal(
      PassphraseEntryVisibility.new,
      name: r'passphraseEntryVisibilityProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$passphraseEntryVisibilityHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PassphraseEntryVisibility = Notifier<int>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
