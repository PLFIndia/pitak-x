// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

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
String _$findByIsbnUseCaseHash() => r'07df33f26a0552cc6ca88844a7ff312a7537e3d1';

/// Finds a library book by exact ISBN (S34: quick-add scan routing — an
/// already-catalogued scan opens the existing book, not the add form).
///
/// Copied from [findByIsbnUseCase].
@ProviderFor(findByIsbnUseCase)
final findByIsbnUseCaseProvider =
    AutoDisposeFutureProvider<FindByIsbnUseCase>.internal(
      findByIsbnUseCase,
      name: r'findByIsbnUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$findByIsbnUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FindByIsbnUseCaseRef = AutoDisposeFutureProviderRef<FindByIsbnUseCase>;
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
String _$bookByIdHash() => r'f7ac65edbecd807956445160bedf1cfac802390d';

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

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
