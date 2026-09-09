// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_cover_materializer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$remoteCoverMaterializerHash() =>
    r'eed29d9a11c583dc4e8f3565b3c46b2914094e11';

/// Schedules at-most-once, serialised remote-cover downloads for the session.
///
/// Copied from [RemoteCoverMaterializer].
@ProviderFor(RemoteCoverMaterializer)
final remoteCoverMaterializerProvider =
    NotifierProvider<RemoteCoverMaterializer, void>.internal(
      RemoteCoverMaterializer.new,
      name: r'remoteCoverMaterializerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$remoteCoverMaterializerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RemoteCoverMaterializer = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
