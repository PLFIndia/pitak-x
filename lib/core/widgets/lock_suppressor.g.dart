// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lock_suppressor.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$lockSuppressorHash() => r'9dda3f93cdb6478bed4289757b32550a5991dc8a';

/// Holds whether the next background/foreground cycle should bypass the lock.
///
/// keepAlive: the flag must survive across the widget rebuilds that happen when
/// the app backgrounds for the external activity; an autoDispose provider could
/// be torn down at exactly the wrong moment.
///
/// Copied from [LockSuppressor].
@ProviderFor(LockSuppressor)
final lockSuppressorProvider = NotifierProvider<LockSuppressor, bool>.internal(
  LockSuppressor.new,
  name: r'lockSuppressorProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$lockSuppressorHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$LockSuppressor = Notifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
