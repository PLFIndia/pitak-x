// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$catalogueItemRepositoryHash() =>
    r'675618adc3ede927788dcf037d7f51f739305674';

/// Library books repository.
///
/// Copied from [catalogueItemRepository].
@ProviderFor(catalogueItemRepository)
final catalogueItemRepositoryProvider =
    AutoDisposeFutureProvider<CatalogueItemRepository>.internal(
      catalogueItemRepository,
      name: r'catalogueItemRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$catalogueItemRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CatalogueItemRepositoryRef =
    AutoDisposeFutureProviderRef<CatalogueItemRepository>;
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
String _$coverFileJanitorHash() => r'abef82436839e0d512d4e33a049c5ff368c8ffc0';

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
String _$libraryLanguagesHash() => r'ef1ac5008e41ad2b566663470107b12e399e8ae1';

/// Distinct non-blank languages present in the library (filter-chip facets).
///
/// N04: watches [libraryControllerProvider] as the mutation signal (same
/// pattern as [catalogueItemById]) — watching only the repository OBJECT never
/// fires, so without this an add/edit/import/restore left the chips stale.
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
String _$librarySourceDetailsHash() =>
    r'd4e84d00665b366a84943f25a2d2c4a5c3ca1195';

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

/// Distinct non-blank source details (donor / seller names…) recorded under
/// one [ItemSourceType] — the Export screen's "source detail" picker values.
///
/// Same freshness rule as [libraryLanguages]: watches
/// [libraryControllerProvider] as the mutation signal so an edit that renames
/// a donor is reflected the next time the picker opens. A repository failure
/// degrades to an empty list — the picker then offers "Any", and the export
/// itself still runs; nothing here is worth blocking the screen for.
///
/// Copied from [librarySourceDetails].
@ProviderFor(librarySourceDetails)
const librarySourceDetailsProvider = LibrarySourceDetailsFamily();

/// Distinct non-blank source details (donor / seller names…) recorded under
/// one [ItemSourceType] — the Export screen's "source detail" picker values.
///
/// Same freshness rule as [libraryLanguages]: watches
/// [libraryControllerProvider] as the mutation signal so an edit that renames
/// a donor is reflected the next time the picker opens. A repository failure
/// degrades to an empty list — the picker then offers "Any", and the export
/// itself still runs; nothing here is worth blocking the screen for.
///
/// Copied from [librarySourceDetails].
class LibrarySourceDetailsFamily extends Family<AsyncValue<List<String>>> {
  /// Distinct non-blank source details (donor / seller names…) recorded under
  /// one [ItemSourceType] — the Export screen's "source detail" picker values.
  ///
  /// Same freshness rule as [libraryLanguages]: watches
  /// [libraryControllerProvider] as the mutation signal so an edit that renames
  /// a donor is reflected the next time the picker opens. A repository failure
  /// degrades to an empty list — the picker then offers "Any", and the export
  /// itself still runs; nothing here is worth blocking the screen for.
  ///
  /// Copied from [librarySourceDetails].
  const LibrarySourceDetailsFamily();

  /// Distinct non-blank source details (donor / seller names…) recorded under
  /// one [ItemSourceType] — the Export screen's "source detail" picker values.
  ///
  /// Same freshness rule as [libraryLanguages]: watches
  /// [libraryControllerProvider] as the mutation signal so an edit that renames
  /// a donor is reflected the next time the picker opens. A repository failure
  /// degrades to an empty list — the picker then offers "Any", and the export
  /// itself still runs; nothing here is worth blocking the screen for.
  ///
  /// Copied from [librarySourceDetails].
  LibrarySourceDetailsProvider call(ItemSourceType type) {
    return LibrarySourceDetailsProvider(type);
  }

  @override
  LibrarySourceDetailsProvider getProviderOverride(
    covariant LibrarySourceDetailsProvider provider,
  ) {
    return call(provider.type);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'librarySourceDetailsProvider';
}

/// Distinct non-blank source details (donor / seller names…) recorded under
/// one [ItemSourceType] — the Export screen's "source detail" picker values.
///
/// Same freshness rule as [libraryLanguages]: watches
/// [libraryControllerProvider] as the mutation signal so an edit that renames
/// a donor is reflected the next time the picker opens. A repository failure
/// degrades to an empty list — the picker then offers "Any", and the export
/// itself still runs; nothing here is worth blocking the screen for.
///
/// Copied from [librarySourceDetails].
class LibrarySourceDetailsProvider
    extends AutoDisposeFutureProvider<List<String>> {
  /// Distinct non-blank source details (donor / seller names…) recorded under
  /// one [ItemSourceType] — the Export screen's "source detail" picker values.
  ///
  /// Same freshness rule as [libraryLanguages]: watches
  /// [libraryControllerProvider] as the mutation signal so an edit that renames
  /// a donor is reflected the next time the picker opens. A repository failure
  /// degrades to an empty list — the picker then offers "Any", and the export
  /// itself still runs; nothing here is worth blocking the screen for.
  ///
  /// Copied from [librarySourceDetails].
  LibrarySourceDetailsProvider(ItemSourceType type)
    : this._internal(
        (ref) => librarySourceDetails(ref as LibrarySourceDetailsRef, type),
        from: librarySourceDetailsProvider,
        name: r'librarySourceDetailsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$librarySourceDetailsHash,
        dependencies: LibrarySourceDetailsFamily._dependencies,
        allTransitiveDependencies:
            LibrarySourceDetailsFamily._allTransitiveDependencies,
        type: type,
      );

  LibrarySourceDetailsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.type,
  }) : super.internal();

  final ItemSourceType type;

  @override
  Override overrideWith(
    FutureOr<List<String>> Function(LibrarySourceDetailsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LibrarySourceDetailsProvider._internal(
        (ref) => create(ref as LibrarySourceDetailsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        type: type,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<String>> createElement() {
    return _LibrarySourceDetailsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LibrarySourceDetailsProvider && other.type == type;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, type.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin LibrarySourceDetailsRef on AutoDisposeFutureProviderRef<List<String>> {
  /// The parameter `type` of this provider.
  ItemSourceType get type;
}

class _LibrarySourceDetailsProviderElement
    extends AutoDisposeFutureProviderElement<List<String>>
    with LibrarySourceDetailsRef {
  _LibrarySourceDetailsProviderElement(super.provider);

  @override
  ItemSourceType get type => (origin as LibrarySourceDetailsProvider).type;
}

String _$addCatalogueItemUseCaseHash() =>
    r'dbea5042e28c5c9e919fc304633f082c1236d60c';

/// Adds a new book to the library (title-required validation + persist).
///
/// Copied from [addCatalogueItemUseCase].
@ProviderFor(addCatalogueItemUseCase)
final addCatalogueItemUseCaseProvider =
    AutoDisposeFutureProvider<AddCatalogueItemUseCase>.internal(
      addCatalogueItemUseCase,
      name: r'addCatalogueItemUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addCatalogueItemUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddCatalogueItemUseCaseRef =
    AutoDisposeFutureProviderRef<AddCatalogueItemUseCase>;
String _$findByIsbnUseCaseHash() => r'a08785cfd719c96d8e4f81674981313557faf4d3';

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
String _$updateCatalogueItemUseCaseHash() =>
    r'de53d18b42aa3ba130cf39406b2ddeeb6b6ef49c';

/// Updates an existing library book (title-required, id-immutable).
///
/// Copied from [updateCatalogueItemUseCase].
@ProviderFor(updateCatalogueItemUseCase)
final updateCatalogueItemUseCaseProvider =
    AutoDisposeFutureProvider<UpdateCatalogueItemUseCase>.internal(
      updateCatalogueItemUseCase,
      name: r'updateCatalogueItemUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$updateCatalogueItemUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpdateCatalogueItemUseCaseRef =
    AutoDisposeFutureProviderRef<UpdateCatalogueItemUseCase>;
String _$deleteCatalogueItemUseCaseHash() =>
    r'bfa700b1756c6170f7bd9776f4700a603525713c';

/// Hard-deletes a library book, purging its vault loans when unlocked (#27/D3).
/// The vault side is the session controller (it satisfies [VaultLoanPurger]).
///
/// Copied from [deleteCatalogueItemUseCase].
@ProviderFor(deleteCatalogueItemUseCase)
final deleteCatalogueItemUseCaseProvider =
    AutoDisposeFutureProvider<DeleteCatalogueItemUseCase>.internal(
      deleteCatalogueItemUseCase,
      name: r'deleteCatalogueItemUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$deleteCatalogueItemUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeleteCatalogueItemUseCaseRef =
    AutoDisposeFutureProviderRef<DeleteCatalogueItemUseCase>;
String _$catalogueItemByIdHash() => r'a4ac06de8855a15aecf641a58fbbd1f5f057bb4f';

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `CatalogueItem` the list row was tapped with: a
/// detail page can stay open while the row changes underneath it — a cover
/// captured on that very page rewrites `coverUrl`, the remote-cover
/// materializer may swap an `https://` reference for a local file, an edit
/// saves new fields. A snapshot handed in at push time never learns any of
/// this, and passing it on to the edit form wrote stale values back over the
/// fresh row (a cover file the janitor had already deleted came back as the
/// row's cover).
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
/// Copied from [catalogueItemById].
@ProviderFor(catalogueItemById)
const catalogueItemByIdProvider = CatalogueItemByIdFamily();

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `CatalogueItem` the list row was tapped with: a
/// detail page can stay open while the row changes underneath it — a cover
/// captured on that very page rewrites `coverUrl`, the remote-cover
/// materializer may swap an `https://` reference for a local file, an edit
/// saves new fields. A snapshot handed in at push time never learns any of
/// this, and passing it on to the edit form wrote stale values back over the
/// fresh row (a cover file the janitor had already deleted came back as the
/// row's cover).
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
/// Copied from [catalogueItemById].
class CatalogueItemByIdFamily extends Family<AsyncValue<CatalogueItem?>> {
  /// One library book, observed by id, for a detail screen (N03).
  ///
  /// Why a provider and not the `CatalogueItem` the list row was tapped with: a
  /// detail page can stay open while the row changes underneath it — a cover
  /// captured on that very page rewrites `coverUrl`, the remote-cover
  /// materializer may swap an `https://` reference for a local file, an edit
  /// saves new fields. A snapshot handed in at push time never learns any of
  /// this, and passing it on to the edit form wrote stale values back over the
  /// fresh row (a cover file the janitor had already deleted came back as the
  /// row's cover).
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
  /// Copied from [catalogueItemById].
  const CatalogueItemByIdFamily();

  /// One library book, observed by id, for a detail screen (N03).
  ///
  /// Why a provider and not the `CatalogueItem` the list row was tapped with: a
  /// detail page can stay open while the row changes underneath it — a cover
  /// captured on that very page rewrites `coverUrl`, the remote-cover
  /// materializer may swap an `https://` reference for a local file, an edit
  /// saves new fields. A snapshot handed in at push time never learns any of
  /// this, and passing it on to the edit form wrote stale values back over the
  /// fresh row (a cover file the janitor had already deleted came back as the
  /// row's cover).
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
  /// Copied from [catalogueItemById].
  CatalogueItemByIdProvider call(int bookId) {
    return CatalogueItemByIdProvider(bookId);
  }

  @override
  CatalogueItemByIdProvider getProviderOverride(
    covariant CatalogueItemByIdProvider provider,
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
  String? get name => r'catalogueItemByIdProvider';
}

/// One library book, observed by id, for a detail screen (N03).
///
/// Why a provider and not the `CatalogueItem` the list row was tapped with: a
/// detail page can stay open while the row changes underneath it — a cover
/// captured on that very page rewrites `coverUrl`, the remote-cover
/// materializer may swap an `https://` reference for a local file, an edit
/// saves new fields. A snapshot handed in at push time never learns any of
/// this, and passing it on to the edit form wrote stale values back over the
/// fresh row (a cover file the janitor had already deleted came back as the
/// row's cover).
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
/// Copied from [catalogueItemById].
class CatalogueItemByIdProvider
    extends AutoDisposeFutureProvider<CatalogueItem?> {
  /// One library book, observed by id, for a detail screen (N03).
  ///
  /// Why a provider and not the `CatalogueItem` the list row was tapped with: a
  /// detail page can stay open while the row changes underneath it — a cover
  /// captured on that very page rewrites `coverUrl`, the remote-cover
  /// materializer may swap an `https://` reference for a local file, an edit
  /// saves new fields. A snapshot handed in at push time never learns any of
  /// this, and passing it on to the edit form wrote stale values back over the
  /// fresh row (a cover file the janitor had already deleted came back as the
  /// row's cover).
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
  /// Copied from [catalogueItemById].
  CatalogueItemByIdProvider(int bookId)
    : this._internal(
        (ref) => catalogueItemById(ref as CatalogueItemByIdRef, bookId),
        from: catalogueItemByIdProvider,
        name: r'catalogueItemByIdProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$catalogueItemByIdHash,
        dependencies: CatalogueItemByIdFamily._dependencies,
        allTransitiveDependencies:
            CatalogueItemByIdFamily._allTransitiveDependencies,
        bookId: bookId,
      );

  CatalogueItemByIdProvider._internal(
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
    FutureOr<CatalogueItem?> Function(CatalogueItemByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CatalogueItemByIdProvider._internal(
        (ref) => create(ref as CatalogueItemByIdRef),
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
  AutoDisposeFutureProviderElement<CatalogueItem?> createElement() {
    return _CatalogueItemByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CatalogueItemByIdProvider && other.bookId == bookId;
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
mixin CatalogueItemByIdRef on AutoDisposeFutureProviderRef<CatalogueItem?> {
  /// The parameter `bookId` of this provider.
  int get bookId;
}

class _CatalogueItemByIdProviderElement
    extends AutoDisposeFutureProviderElement<CatalogueItem?>
    with CatalogueItemByIdRef {
  _CatalogueItemByIdProviderElement(super.provider);

  @override
  int get bookId => (origin as CatalogueItemByIdProvider).bookId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
