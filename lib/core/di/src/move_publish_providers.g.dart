// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'move_publish_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$configuredMoveTargetResolverHash() =>
    r'ba0596608dadc4fb64a8b53b61e1bb1f61e2574b';

/// Resolves the two exact endpoints for setup checks and new moves.
///
/// Copied from [configuredMoveTargetResolver].
@ProviderFor(configuredMoveTargetResolver)
final configuredMoveTargetResolverProvider =
    AutoDisposeFutureProvider<ConfiguredMoveTargetResolver>.internal(
      configuredMoveTargetResolver,
      name: r'configuredMoveTargetResolverProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$configuredMoveTargetResolverHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ConfiguredMoveTargetResolverRef =
    AutoDisposeFutureProviderRef<ConfiguredMoveTargetResolver>;
String _$moveSiteUseCaseHash() => r'58bf1237d362762d87339aea8a3890b66145e89b';

/// Wires both host operations over the same builders, queue and journal.
///
/// Copied from [moveSiteUseCase].
@ProviderFor(moveSiteUseCase)
final moveSiteUseCaseProvider =
    AutoDisposeFutureProvider<MoveSiteUseCaseFactory>.internal(
      moveSiteUseCase,
      name: r'moveSiteUseCaseProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$moveSiteUseCaseHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MoveSiteUseCaseRef =
    AutoDisposeFutureProviderRef<MoveSiteUseCaseFactory>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
