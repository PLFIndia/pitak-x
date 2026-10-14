// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
