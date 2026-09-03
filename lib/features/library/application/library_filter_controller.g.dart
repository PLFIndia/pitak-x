// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_filter_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$libraryLanguageFilterHash() =>
    r'697ad835f01125dc34a30bbc64c72855068fdbe3';

/// The active language facet for the library list; null = all languages.
///
/// keepAlive: the chosen filter must survive navigating away from and back to
/// the Library screen (opening a book and returning must not silently reset
/// it), so it lives for the app session like the list's other view state.
///
/// Copied from [LibraryLanguageFilter].
@ProviderFor(LibraryLanguageFilter)
final libraryLanguageFilterProvider =
    NotifierProvider<LibraryLanguageFilter, String?>.internal(
      LibraryLanguageFilter.new,
      name: r'libraryLanguageFilterProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$libraryLanguageFilterHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LibraryLanguageFilter = Notifier<String?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
