// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalogue_changes.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$catalogueChangesHash() => r'aadc0589166748222ece38b58d6237c52ea180a1';

/// Counts the changes of catalogue data during this app run.
///
/// keepAlive: the flows that say "changed" (an import, a restore, a cover
/// download) outlive the screens that started them, and the availability
/// updater, which listens, lives for the whole app run. A count that was
/// thrown away between two listeners would start at 0 again and could hide
/// a change. The state is one integer.
///
/// Copied from [CatalogueChanges].
@ProviderFor(CatalogueChanges)
final catalogueChangesProvider =
    NotifierProvider<CatalogueChanges, int>.internal(
      CatalogueChanges.new,
      name: r'catalogueChangesProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$catalogueChangesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$CatalogueChanges = Notifier<int>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
