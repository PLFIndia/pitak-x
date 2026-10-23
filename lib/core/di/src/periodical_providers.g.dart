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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
