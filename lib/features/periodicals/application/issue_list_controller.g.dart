// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'issue_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$issueListControllerHash() =>
    r'893a195ec6e1543d0bcc618506305418d038a57b';

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

abstract class _$IssueListController
    extends BuildlessAutoDisposeAsyncNotifier<LibraryWindow> {
  late final String periodicalUid;

  FutureOr<LibraryWindow> build(String periodicalUid);
}

/// Loads and pages the issues of one series for the presentation layer.
///
/// Copied from [IssueListController].
@ProviderFor(IssueListController)
const issueListControllerProvider = IssueListControllerFamily();

/// Loads and pages the issues of one series for the presentation layer.
///
/// Copied from [IssueListController].
class IssueListControllerFamily extends Family<AsyncValue<LibraryWindow>> {
  /// Loads and pages the issues of one series for the presentation layer.
  ///
  /// Copied from [IssueListController].
  const IssueListControllerFamily();

  /// Loads and pages the issues of one series for the presentation layer.
  ///
  /// Copied from [IssueListController].
  IssueListControllerProvider call(String periodicalUid) {
    return IssueListControllerProvider(periodicalUid);
  }

  @override
  IssueListControllerProvider getProviderOverride(
    covariant IssueListControllerProvider provider,
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
  String? get name => r'issueListControllerProvider';
}

/// Loads and pages the issues of one series for the presentation layer.
///
/// Copied from [IssueListController].
class IssueListControllerProvider
    extends
        AutoDisposeAsyncNotifierProviderImpl<
          IssueListController,
          LibraryWindow
        > {
  /// Loads and pages the issues of one series for the presentation layer.
  ///
  /// Copied from [IssueListController].
  IssueListControllerProvider(String periodicalUid)
    : this._internal(
        () => IssueListController()..periodicalUid = periodicalUid,
        from: issueListControllerProvider,
        name: r'issueListControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$issueListControllerHash,
        dependencies: IssueListControllerFamily._dependencies,
        allTransitiveDependencies:
            IssueListControllerFamily._allTransitiveDependencies,
        periodicalUid: periodicalUid,
      );

  IssueListControllerProvider._internal(
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
  FutureOr<LibraryWindow> runNotifierBuild(
    covariant IssueListController notifier,
  ) {
    return notifier.build(periodicalUid);
  }

  @override
  Override overrideWith(IssueListController Function() create) {
    return ProviderOverride(
      origin: this,
      override: IssueListControllerProvider._internal(
        () => create()..periodicalUid = periodicalUid,
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
  AutoDisposeAsyncNotifierProviderElement<IssueListController, LibraryWindow>
  createElement() {
    return _IssueListControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is IssueListControllerProvider &&
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
mixin IssueListControllerRef
    on AutoDisposeAsyncNotifierProviderRef<LibraryWindow> {
  /// The parameter `periodicalUid` of this provider.
  String get periodicalUid;
}

class _IssueListControllerProviderElement
    extends
        AutoDisposeAsyncNotifierProviderElement<
          IssueListController,
          LibraryWindow
        >
    with IssueListControllerRef {
  _IssueListControllerProviderElement(super.provider);

  @override
  String get periodicalUid =>
      (origin as IssueListControllerProvider).periodicalUid;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
