// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$libraryControllerHash() => r'6b889d32a25cce36cdeb568fa48abc1ea38615a9';

/// Loads and searches the library book list for the presentation layer.
///
/// Copied from [LibraryController].
@ProviderFor(LibraryController)
final libraryControllerProvider =
    AutoDisposeAsyncNotifierProvider<LibraryController, List<Book>>.internal(
      LibraryController.new,
      name: r'libraryControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$libraryControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LibraryController = AutoDisposeAsyncNotifier<List<Book>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
