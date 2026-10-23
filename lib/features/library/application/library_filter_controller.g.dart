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
String _$libraryKindFilterHash() => r'7a7330f7c7976059ee95f38950e5010f419a0d25';

/// The active item-kind facet for the library list (ADR 0013 U1); null =
/// every kind.
///
/// The chips are a fixed row from `ItemKind.values` (Books · Magazines ·
/// Others) with TOGGLE semantics: tapping the selected chip clears the facet
/// — there is no "All" chip, "none selected" IS all. [toggle] is that rule
/// in one place so the chip row never has to compare state itself.
///
/// keepAlive for the same reason as [LibraryLanguageFilter]: opening an item
/// and coming back must not silently reset the facet.
///
/// Copied from [LibraryKindFilter].
@ProviderFor(LibraryKindFilter)
final libraryKindFilterProvider =
    NotifierProvider<LibraryKindFilter, ItemKind?>.internal(
      LibraryKindFilter.new,
      name: r'libraryKindFilterProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$libraryKindFilterHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LibraryKindFilter = Notifier<ItemKind?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
