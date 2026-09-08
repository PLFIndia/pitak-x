/// Riverpod owner of the active [DataGeneration] (M02).
///
/// Every storage provider that restore replaces — the catalogue database, the
/// covers directory, the vault store — derives its paths from THIS notifier
/// instead of from the raw documents directory. When a restore has built and
/// completed a new generation it calls [ActiveDataGeneration.activate]; the
/// pointer switch happens there, and Riverpod then rebuilds the dependent
/// providers (`ref.watch`) so the whole app moves to the new data set at once.
///
/// keepAlive: the active generation is process-wide state. Losing it would
/// re-run startup recovery (harmless, but pointless) and would let two callers
/// disagree about which generation is live.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_data_generation.g.dart';

/// Resolves (and repairs) the active generation once, then publishes switches.
@Riverpod(keepAlive: true)
class ActiveDataGeneration extends _$ActiveDataGeneration {
  @override
  Future<DataGeneration> build() async {
    final generations = await ref.watch(dataGenerationsProvider.future);
    // Startup recovery + first-launch adoption of the flat layout happen here
    // (see DataGenerations.open). File IO is synchronous and small: one
    // directory listing plus, once per install, a handful of renames.
    return generations.open();
  }

  /// Makes a COMPLETE [generation] live: switches the pointer atomically and
  /// deletes the previous generation, then publishes the new value so every
  /// `ref.watch`er (database, covers, vault store) rebuilds onto it.
  ///
  /// Throws (does not publish) if the switch fails; the old generation is then
  /// still active on disk AND in state, which is the fail-closed outcome.
  Future<DataGeneration> activate(DataGeneration generation) async {
    final generations = await ref.read(dataGenerationsProvider.future);
    final active = generations.activate(generation);
    state = AsyncData(active);
    return active;
  }
}
