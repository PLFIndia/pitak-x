/// A signal that item ids changed meaning (application layer; plan J9, S6).
///
/// `CatalogueKeysReset` bumps it after a restore or an overwrite merge has
/// run; the availability lane listens and forgets the sets it holds in
/// memory, whose keys came from the old ids. A counter, not data: listeners
/// only need to know that it happened.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalogue_ids_changes.g.dart';

/// Counts id-meaning changes during this app run.
///
/// keepAlive: the reset that bumps it lives for the whole app run, and a
/// listener added later must still see a value; the state is one integer.
@Riverpod(keepAlive: true)
class CatalogueIdsChanges extends _$CatalogueIdsChanges {
  @override
  int build() => 0;

  /// Records one change.
  void changed() => state = state + 1;
}
