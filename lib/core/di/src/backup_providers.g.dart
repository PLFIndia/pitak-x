// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$createBackupUseCaseHash() =>
    r'e444f958285769d36aee119c03046a04203a6f09';

/// Creates a `.pitabak` backup of the whole local catalog (#28B): Room-format
/// books/wishlist written from Drift, the persistent vault copied verbatim, and
/// covers bundled — plus the library identity and the saved-libraries list
/// (docs/ARCHITECTURE.md §3 network, both gathered best-effort). Returns the archive
/// bytes for the UI to save.
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
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
