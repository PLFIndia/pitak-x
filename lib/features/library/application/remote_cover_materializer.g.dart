// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_cover_materializer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$remoteCoverMaterializerHash() =>
    r'3252e33b3a3ee470580723af72fa348a10db3c20';

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
