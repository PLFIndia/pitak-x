// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wishlist_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$wishlistControllerHash() =>
    r'2c6f5c93cbf77ac2225341a92191ce2a1ff69b6d';

/// Loads and mutates the wishlist for the presentation layer.
///
/// Copied from [WishlistController].
@ProviderFor(WishlistController)
final wishlistControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      WishlistController,
      List<WishlistBook>
    >.internal(
      WishlistController.new,
      name: r'wishlistControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$wishlistControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$WishlistController = AutoDisposeAsyncNotifier<List<WishlistBook>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
