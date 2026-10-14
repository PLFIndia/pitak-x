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
