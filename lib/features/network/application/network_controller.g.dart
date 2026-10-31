// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$networkListViewHash() => r'ef6bd92c971809f2daa233f8643dd926d15ae38f';

/// The Libraries-tab view in ONE snapshot: the window plus its rows in
/// display order ([NetworkLibrarySort.byDistanceThenName]).
///
/// Why a derived provider and not a sort in the widget's `build` (review
/// M12): a provider recomputes only when its INPUTS change (the window, or
/// the own-pin settings), while a `build`-time sort re-ran on every frame.
/// Returning the window alongside the sorted rows also means the tab renders
/// one consistent snapshot — no frame where the rows are loaded but briefly
/// unsorted.
///
/// Copied from [networkListView].
@ProviderFor(networkListView)
final networkListViewProvider =
    AutoDisposeFutureProvider<
      ({NetworkWindow window, List<NetworkLibrary> rows})
    >.internal(
      networkListView,
      name: r'networkListViewProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$networkListViewHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NetworkListViewRef =
    AutoDisposeFutureProviderRef<
      ({NetworkWindow window, List<NetworkLibrary> rows})
    >;
String _$networkControllerHash() => r'6b19ad11ddae1410eb9fa80d86b264bb271a4f31';

/// Loads the network window and runs its mutations.
///
/// Copied from [NetworkController].
@ProviderFor(NetworkController)
final networkControllerProvider =
    AutoDisposeAsyncNotifierProvider<NetworkController, NetworkWindow>.internal(
      NetworkController.new,
      name: r'networkControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$networkControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$NetworkController = AutoDisposeAsyncNotifier<NetworkWindow>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
