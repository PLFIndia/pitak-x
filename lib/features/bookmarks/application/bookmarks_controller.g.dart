// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmarks_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bookmarksControllerHash() =>
    r'29468ef08a4e3124374f0eb2f3130bddf1f34ce5';

/// Loads + mutates the user's library bookmarks.
///
/// Copied from [BookmarksController].
@ProviderFor(BookmarksController)
final bookmarksControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      BookmarksController,
      List<LibraryBookmark>
    >.internal(
      BookmarksController.new,
      name: r'bookmarksControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$bookmarksControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$BookmarksController = AutoDisposeAsyncNotifier<List<LibraryBookmark>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
