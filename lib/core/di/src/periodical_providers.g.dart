// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'periodical_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$addPeriodicalUseCaseHash() =>
    r'dcacc783f2696e96f8f1922aacd089b08fc18bd3';

/// Adds a new magazine title (validation + ISSN pre-check + persist).
///
/// Copied from [addPeriodicalUseCase].
@ProviderFor(addPeriodicalUseCase)
final addPeriodicalUseCaseProvider =
    AutoDisposeFutureProvider<AddPeriodicalUseCase>.internal(
      addPeriodicalUseCase,
      name: r'addPeriodicalUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addPeriodicalUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddPeriodicalUseCaseRef =
    AutoDisposeFutureProviderRef<AddPeriodicalUseCase>;
String _$updatePeriodicalUseCaseHash() =>
    r'9a87ce4c2108d0d52c91192584542763538211b4';

/// Edits a magazine title and re-projects its issues in one transaction
/// (ADR 0013 D3).
///
/// Copied from [updatePeriodicalUseCase].
@ProviderFor(updatePeriodicalUseCase)
final updatePeriodicalUseCaseProvider =
    AutoDisposeFutureProvider<UpdatePeriodicalUseCase>.internal(
      updatePeriodicalUseCase,
      name: r'updatePeriodicalUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$updatePeriodicalUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpdatePeriodicalUseCaseRef =
    AutoDisposeFutureProviderRef<UpdatePeriodicalUseCase>;
String _$deletePeriodicalUseCaseHash() =>
    r'011e53f347f96402d39edb3f949864db37c5272d';

/// Hard-deletes a magazine title that no issue references (ADR 0013 D8),
/// releasing its cover file through the janitor.
///
/// Copied from [deletePeriodicalUseCase].
@ProviderFor(deletePeriodicalUseCase)
final deletePeriodicalUseCaseProvider =
    AutoDisposeFutureProvider<DeletePeriodicalUseCase>.internal(
      deletePeriodicalUseCase,
      name: r'deletePeriodicalUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$deletePeriodicalUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeletePeriodicalUseCaseRef =
    AutoDisposeFutureProviderRef<DeletePeriodicalUseCase>;
String _$addIssueUseCaseHash() => r'9fc55b1ee01eeb92ca7b4545a20a649058647c82';

/// Adds a magazine issue or bound volume under its series (ADR 0013 D1, D4).
///
/// Copied from [addIssueUseCase].
@ProviderFor(addIssueUseCase)
final addIssueUseCaseProvider =
    AutoDisposeFutureProvider<AddIssueUseCase>.internal(
      addIssueUseCase,
      name: r'addIssueUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$addIssueUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AddIssueUseCaseRef = AutoDisposeFutureProviderRef<AddIssueUseCase>;
String _$updateIssueUseCaseHash() =>
    r'023b569adaabd4f5cc0c153b3053d4876d40e228';

/// Edits an existing magazine issue; refuses a kind change (ADR 0013 D8).
///
/// Copied from [updateIssueUseCase].
@ProviderFor(updateIssueUseCase)
final updateIssueUseCaseProvider =
    AutoDisposeFutureProvider<UpdateIssueUseCase>.internal(
      updateIssueUseCase,
      name: r'updateIssueUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$updateIssueUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UpdateIssueUseCaseRef =
    AutoDisposeFutureProviderRef<UpdateIssueUseCase>;
String _$periodicalByIdHash() => r'4df90a9fb3ccb148280737c5e8ee582d176ebd5e';

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

/// One magazine title, observed by per-device id, for the series detail
/// page and the edit form (same contract as `catalogueItemById`, N03: a
/// page stays open while the row changes underneath it, so it observes the
/// row rather than the snapshot it was pushed with).
///
/// Freshness signals (N04): BOTH mutation signals are watched, value
/// ignored. `periodicalsControllerProvider` fires on every series write
/// (form save, remove/restore, delete); `libraryControllerProvider` fires on
/// every item write — including import, merge and restore, which rewrite
/// periodicals without going through the series controller. Watching only
/// the repository OBJECT would never fire.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError`.
///
/// Copied from [periodicalById].
@ProviderFor(periodicalById)
const periodicalByIdProvider = PeriodicalByIdFamily();

/// One magazine title, observed by per-device id, for the series detail
/// page and the edit form (same contract as `catalogueItemById`, N03: a
/// page stays open while the row changes underneath it, so it observes the
/// row rather than the snapshot it was pushed with).
///
/// Freshness signals (N04): BOTH mutation signals are watched, value
/// ignored. `periodicalsControllerProvider` fires on every series write
/// (form save, remove/restore, delete); `libraryControllerProvider` fires on
/// every item write — including import, merge and restore, which rewrite
/// periodicals without going through the series controller. Watching only
/// the repository OBJECT would never fire.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError`.
///
/// Copied from [periodicalById].
class PeriodicalByIdFamily extends Family<AsyncValue<Periodical?>> {
  /// One magazine title, observed by per-device id, for the series detail
  /// page and the edit form (same contract as `catalogueItemById`, N03: a
  /// page stays open while the row changes underneath it, so it observes the
  /// row rather than the snapshot it was pushed with).
  ///
  /// Freshness signals (N04): BOTH mutation signals are watched, value
  /// ignored. `periodicalsControllerProvider` fires on every series write
  /// (form save, remove/restore, delete); `libraryControllerProvider` fires on
  /// every item write — including import, merge and restore, which rewrite
  /// periodicals without going through the series controller. Watching only
  /// the repository OBJECT would never fire.
  ///
  /// `null` = the row no longer exists. A repository `Left` is thrown so the
  /// screen sees `AsyncError`.
  ///
  /// Copied from [periodicalById].
  const PeriodicalByIdFamily();

  /// One magazine title, observed by per-device id, for the series detail
  /// page and the edit form (same contract as `catalogueItemById`, N03: a
  /// page stays open while the row changes underneath it, so it observes the
  /// row rather than the snapshot it was pushed with).
  ///
  /// Freshness signals (N04): BOTH mutation signals are watched, value
  /// ignored. `periodicalsControllerProvider` fires on every series write
  /// (form save, remove/restore, delete); `libraryControllerProvider` fires on
  /// every item write — including import, merge and restore, which rewrite
  /// periodicals without going through the series controller. Watching only
  /// the repository OBJECT would never fire.
  ///
  /// `null` = the row no longer exists. A repository `Left` is thrown so the
  /// screen sees `AsyncError`.
  ///
  /// Copied from [periodicalById].
  PeriodicalByIdProvider call(int id) {
    return PeriodicalByIdProvider(id);
  }

  @override
  PeriodicalByIdProvider getProviderOverride(
    covariant PeriodicalByIdProvider provider,
  ) {
    return call(provider.id);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'periodicalByIdProvider';
}

/// One magazine title, observed by per-device id, for the series detail
/// page and the edit form (same contract as `catalogueItemById`, N03: a
/// page stays open while the row changes underneath it, so it observes the
/// row rather than the snapshot it was pushed with).
///
/// Freshness signals (N04): BOTH mutation signals are watched, value
/// ignored. `periodicalsControllerProvider` fires on every series write
/// (form save, remove/restore, delete); `libraryControllerProvider` fires on
/// every item write — including import, merge and restore, which rewrite
/// periodicals without going through the series controller. Watching only
/// the repository OBJECT would never fire.
///
/// `null` = the row no longer exists. A repository `Left` is thrown so the
/// screen sees `AsyncError`.
///
/// Copied from [periodicalById].
class PeriodicalByIdProvider extends AutoDisposeFutureProvider<Periodical?> {
  /// One magazine title, observed by per-device id, for the series detail
  /// page and the edit form (same contract as `catalogueItemById`, N03: a
  /// page stays open while the row changes underneath it, so it observes the
  /// row rather than the snapshot it was pushed with).
  ///
  /// Freshness signals (N04): BOTH mutation signals are watched, value
  /// ignored. `periodicalsControllerProvider` fires on every series write
  /// (form save, remove/restore, delete); `libraryControllerProvider` fires on
  /// every item write — including import, merge and restore, which rewrite
  /// periodicals without going through the series controller. Watching only
  /// the repository OBJECT would never fire.
  ///
  /// `null` = the row no longer exists. A repository `Left` is thrown so the
  /// screen sees `AsyncError`.
  ///
  /// Copied from [periodicalById].
  PeriodicalByIdProvider(int id)
    : this._internal(
        (ref) => periodicalById(ref as PeriodicalByIdRef, id),
        from: periodicalByIdProvider,
        name: r'periodicalByIdProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$periodicalByIdHash,
        dependencies: PeriodicalByIdFamily._dependencies,
        allTransitiveDependencies:
            PeriodicalByIdFamily._allTransitiveDependencies,
        id: id,
      );

  PeriodicalByIdProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final int id;

  @override
  Override overrideWith(
    FutureOr<Periodical?> Function(PeriodicalByIdRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PeriodicalByIdProvider._internal(
        (ref) => create(ref as PeriodicalByIdRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Periodical?> createElement() {
    return _PeriodicalByIdProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PeriodicalByIdProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PeriodicalByIdRef on AutoDisposeFutureProviderRef<Periodical?> {
  /// The parameter `id` of this provider.
  int get id;
}

class _PeriodicalByIdProviderElement
    extends AutoDisposeFutureProviderElement<Periodical?>
    with PeriodicalByIdRef {
  _PeriodicalByIdProviderElement(super.provider);

  @override
  int get id => (origin as PeriodicalByIdProvider).id;
}

String _$periodicalByUidHash() => r'23d33946562ebdb847d69cd7ce5b3340b0dcc7d2';

/// One magazine title, observed by its stable `periodicalUid` — the key an
/// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
/// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
/// per-device id. Same freshness contract as [periodicalById].
///
/// `null` = no such series (a blank uid never matches).
///
/// Copied from [periodicalByUid].
@ProviderFor(periodicalByUid)
const periodicalByUidProvider = PeriodicalByUidFamily();

/// One magazine title, observed by its stable `periodicalUid` — the key an
/// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
/// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
/// per-device id. Same freshness contract as [periodicalById].
///
/// `null` = no such series (a blank uid never matches).
///
/// Copied from [periodicalByUid].
class PeriodicalByUidFamily extends Family<AsyncValue<Periodical?>> {
  /// One magazine title, observed by its stable `periodicalUid` — the key an
  /// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
  /// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
  /// per-device id. Same freshness contract as [periodicalById].
  ///
  /// `null` = no such series (a blank uid never matches).
  ///
  /// Copied from [periodicalByUid].
  const PeriodicalByUidFamily();

  /// One magazine title, observed by its stable `periodicalUid` — the key an
  /// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
  /// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
  /// per-device id. Same freshness contract as [periodicalById].
  ///
  /// `null` = no such series (a blank uid never matches).
  ///
  /// Copied from [periodicalByUid].
  PeriodicalByUidProvider call(String periodicalUid) {
    return PeriodicalByUidProvider(periodicalUid);
  }

  @override
  PeriodicalByUidProvider getProviderOverride(
    covariant PeriodicalByUidProvider provider,
  ) {
    return call(provider.periodicalUid);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'periodicalByUidProvider';
}

/// One magazine title, observed by its stable `periodicalUid` — the key an
/// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
/// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
/// per-device id. Same freshness contract as [periodicalById].
///
/// `null` = no such series (a blank uid never matches).
///
/// Copied from [periodicalByUid].
class PeriodicalByUidProvider extends AutoDisposeFutureProvider<Periodical?> {
  /// One magazine title, observed by its stable `periodicalUid` — the key an
  /// issue's `IssueOf.periodicalUid` carries, so an issue's detail page can
  /// resolve "Open series" and its fallback cover (ADR 0014 W4) without a
  /// per-device id. Same freshness contract as [periodicalById].
  ///
  /// `null` = no such series (a blank uid never matches).
  ///
  /// Copied from [periodicalByUid].
  PeriodicalByUidProvider(String periodicalUid)
    : this._internal(
        (ref) => periodicalByUid(ref as PeriodicalByUidRef, periodicalUid),
        from: periodicalByUidProvider,
        name: r'periodicalByUidProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$periodicalByUidHash,
        dependencies: PeriodicalByUidFamily._dependencies,
        allTransitiveDependencies:
            PeriodicalByUidFamily._allTransitiveDependencies,
        periodicalUid: periodicalUid,
      );

  PeriodicalByUidProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.periodicalUid,
  }) : super.internal();

  final String periodicalUid;

  @override
  Override overrideWith(
    FutureOr<Periodical?> Function(PeriodicalByUidRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PeriodicalByUidProvider._internal(
        (ref) => create(ref as PeriodicalByUidRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        periodicalUid: periodicalUid,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Periodical?> createElement() {
    return _PeriodicalByUidProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PeriodicalByUidProvider &&
        other.periodicalUid == periodicalUid;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, periodicalUid.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PeriodicalByUidRef on AutoDisposeFutureProviderRef<Periodical?> {
  /// The parameter `periodicalUid` of this provider.
  String get periodicalUid;
}

class _PeriodicalByUidProviderElement
    extends AutoDisposeFutureProviderElement<Periodical?>
    with PeriodicalByUidRef {
  _PeriodicalByUidProviderElement(super.provider);

  @override
  String get periodicalUid => (origin as PeriodicalByUidProvider).periodicalUid;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
