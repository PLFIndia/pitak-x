// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'periodicals_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$periodicalsControllerHash() =>
    r'8a5c3724da03e547b13988f61e0283ca71317f50';

/// Loads the magazine titles for the presentation layer.
///
/// Copied from [PeriodicalsController].
@ProviderFor(PeriodicalsController)
final periodicalsControllerProvider =
    AutoDisposeAsyncNotifierProvider<
      PeriodicalsController,
      List<PeriodicalListEntry>
    >.internal(
      PeriodicalsController.new,
      name: r'periodicalsControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$periodicalsControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PeriodicalsController =
    AutoDisposeAsyncNotifier<List<PeriodicalListEntry>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
