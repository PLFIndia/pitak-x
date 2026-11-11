// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$backupWorkAreaHash() => r'a28d6f9ee8616bd719f813886d65799ce364bd38';

/// The private folders backups are built in (backup rework BR4): one new
/// folder per build under the app's temporary directory, and the one place
/// that removes them again.
///
/// keepAlive (justified): this object remembers which folders are IN USE by
/// a build of this app session, so that a sweep never deletes a backup that
/// is being written or shared. An auto-disposed instance would forget that
/// between two reads.
///
/// Copied from [backupWorkArea].
@ProviderFor(backupWorkArea)
final backupWorkAreaProvider = FutureProvider<BackupWorkArea>.internal(
  backupWorkArea,
  name: r'backupWorkAreaProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$backupWorkAreaHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BackupWorkAreaRef = FutureProviderRef<BackupWorkArea>;
String _$staleBackupWorkSweepHash() =>
    r'd50a26337f78227eda1aa7b07506ab38d1c9420d';

/// One-time clean-up per app start: removes what a backup left behind when
/// the app was killed in the middle of it (a plain copy of the library).
/// Triggered next to the cover sweep, by the Library screen's first build.
///
/// keepAlive (justified): "once per app session" is the whole point, as for
/// `orphanCoverSweep`. The result is not shown anywhere: when something
/// could not be removed, the next start (and the next backup) tries again.
///
/// Copied from [staleBackupWorkSweep].
@ProviderFor(staleBackupWorkSweep)
final staleBackupWorkSweepProvider = FutureProvider<void>.internal(
  staleBackupWorkSweep,
  name: r'staleBackupWorkSweepProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$staleBackupWorkSweepHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef StaleBackupWorkSweepRef = FutureProviderRef<void>;
String _$createBackupUseCaseHash() =>
    r'e6059fa54fd163731b7adc8fa2d37cd2faeb60ef';

/// Creates a `.pitabak` backup of the whole local catalog (#28B): Room-format
/// books/wishlist written from Drift, the persistent vault copied verbatim, and
/// covers bundled — plus the library identity and the saved-libraries list
/// (docs/ARCHITECTURE.md §3 network) and the website publishing record (plan
/// CV6), all gathered best-effort. Returns where the finished archive file
/// is, for the UI to share and then discard.
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
String _$restoreBackupHash() => r'81a08374eacb31a27c8900d6950de4bfa967453f';

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
