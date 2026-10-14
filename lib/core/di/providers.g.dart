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
String _$wishlistBookByIdHash() => r'176febc233f1cf5a199182f23de5b012c91873dd';

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
    r'3be3d0337d2d255a58b32cb5c4aa18a49e1ab251';

/// Multi-maintainer library merge use case (PLAN-merge.md): reconciles an
/// incoming Pitaka-JSON file with the local catalogue behind the library-ID
/// gate. The library identity (ID gate + Join/Overwrite adoption) goes through
/// `SettingsController` — the single serialised settings writer — via the
/// `LibraryNamespace` port, so the drawer/title/export name update the moment
/// a merge adopts a library (N07; same shape as the replacement guard below).
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
    r'cde9a9cd8e0f40a1b167cefe49dec8e4b05ea7d6';

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
