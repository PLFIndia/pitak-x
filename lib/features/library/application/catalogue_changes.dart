/// The app's "catalogue data changed" signal (application layer).
///
/// Review findings P3-M4, P4-M2 and P4-m13 (ADR 0031): until November 2026
/// the Library list's own state doubled as this signal. Everything that
/// shows catalogue data watched the list, so it all ran again whenever the
/// user only scrolled or typed, and a write could tell the others only by
/// making the list load again.
///
/// Now the two are apart. Every flow that WRITES catalogue data calls
/// [CatalogueChanges.changed] once the write is done (decision D151: the
/// write paths say it, at the moment each of them chooses). Everything that
/// shows catalogue data watches this provider and reads again. The Library
/// list is one of those listeners.
///
/// A counter, not data: listeners only need to know that something
/// happened. The same pattern as `CatalogueIdsChanges`, which says the
/// narrower thing "item ids changed meaning".
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catalogue_changes.g.dart';

/// Counts the changes of catalogue data during this app run.
///
/// keepAlive: the flows that say "changed" (an import, a restore, a cover
/// download) outlive the screens that started them, and the availability
/// updater, which listens, lives for the whole app run. A count that was
/// thrown away between two listeners would start at 0 again and could hide
/// a change. The state is one integer.
@Riverpod(keepAlive: true)
class CatalogueChanges extends _$CatalogueChanges {
  @override
  int build() => 0;

  /// Records one change. Call it AFTER the write has succeeded: listeners
  /// read the catalogue again as soon as they hear it.
  void changed() => state = state + 1;
}
