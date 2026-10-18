/// The network window controller (network application layer, AGENTS.md §4;
/// libNetwork.md §5.1).
///
/// [NetworkWindow] is everything the Libraries tab renders in one immutable
/// snapshot: the rows (single truth: the repository), the last refresh report
/// and the "last refreshed" stamp (both owned by the keepAlive
/// `NetworkRefreshController`, so they survive navigation). Mutations
/// (add-by-URL, remove, membership decisions) go through here, hit the
/// repository, and then re-read — the window never patches itself from
/// memory, so what the list shows is always what is stored.
///
/// This replaces the S3 stopgap `networkRowsProvider` (handoff §3): screens
/// watch ONE provider and the remove path no longer calls the repository
/// from presentation.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_library_sort.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_controller.g.dart';

/// What an add-by-URL attempt did — the UI maps each case to one plain
/// sentence (no raw failures surface).
enum NetworkAddOutcome {
  /// The row was saved.
  added,

  /// A row with that site URL already exists (the URL is the identity, D13 —
  /// duplicates collapse instead of confusing the user with a second row).
  alreadySaved,

  /// The URL failed the [BookmarkUrl] allow-list.
  invalidUrl,

  /// The repository refused the write.
  storageFailed,
}

/// One immutable snapshot of the network screen's data.
///
/// Hand-written rather than `freezed` ON PURPOSE (review Lows): nothing in
/// `lib/features` uses freezed — `AppSettings`, `RefreshReport` and
/// `RestoreSummary` are all plain immutable classes, and AGENTS.md's
/// one-blessed-way rule beats the §7 shorthand here. No caller needs value
/// equality (Riverpod rebuilds on identity, and no `select` diffs this), so
/// the generated `==`/`copyWith` would be code we cannot feel. Revisit only
/// if the app adopts freezed wholesale.
final class NetworkWindow {
  /// Creates a window.
  const NetworkWindow({
    required this.rows,
    this.lastReport,
    this.lastRefreshedAt,
  });

  /// All saved rows in repository order (`sortOrder`, then name).
  final List<NetworkLibrary> rows;

  /// The last refresh run's report; null when none ran yet.
  final RefreshReport? lastReport;

  /// Epoch millis of the last refresh run; null when none ran yet.
  final int? lastRefreshedAt;
}

/// The Libraries-tab view in ONE snapshot: the window plus its rows in
/// display order ([NetworkLibrarySort.byDistanceThenName]).
///
/// Why a derived provider and not a sort in the widget's `build` (review
/// M12): a provider recomputes only when its INPUTS change (the window, or
/// the own-pin settings), while a `build`-time sort re-ran on every frame.
/// Returning the window alongside the sorted rows also means the tab renders
/// one consistent snapshot — no frame where the rows are loaded but briefly
/// unsorted.
@riverpod
Future<({NetworkWindow window, List<NetworkLibrary> rows})> networkListView(
  NetworkListViewRef ref,
) async {
  final window = await ref.watch(networkControllerProvider.future);
  // The own pin for distance sorting = the location THIS library publishes
  // (D7 mapping in one place; off/unparseable ⇒ no own pin ⇒ name order).
  // AWAITED (not valueOrNull): the first frame the tab renders is already
  // sorted — no flash of name order while settings load. A settings failure
  // degrades to name order rather than breaking the tab. (Non-final: Dart's
  // definite-assignment rule forbids assigning a final in try AND catch.)
  AppSettings? settings;
  try {
    settings = await ref.watch(settingsControllerProvider.future);
  } on Object {
    settings = null;
  }
  final own = settings == null
      ? null
      : BuildOwnDescriptor.ownLocation(
          sharing: settings.publishLocationSharing,
          gps: settings.publishContactGps,
        );
  return (
    window: window,
    rows: NetworkLibrarySort.byDistanceThenName(window.rows, own),
  );
}

/// Loads the network window and runs its mutations.
@riverpod
class NetworkController extends _$NetworkController {
  @override
  FutureOr<NetworkWindow> build() async {
    // The listener registers BEFORE any await (review Lows): a refresh that
    // settles while the repository future is still in flight would otherwise
    // fire its settle transition with no listener attached and the window
    // would miss the invalidation.
    // Re-read when a refresh run settles (a cancelled run too — it applies
    // partial results). listen, not watch: a run in flight must not rebuild
    // this window, and the settle transition is the only interesting one.
    ref.listen(networkRefreshControllerProvider, (previous, next) {
      final wasRunning = previous?.isLoading ?? false;
      if (wasRunning && !next.isLoading) ref.invalidateSelf();
    });
    final repo = await ref.watch(networkRepositoryProvider.future);
    final rows = await repo.loadAll();
    // Report + stamp live in the keepAlive refresh controller; a plain read
    // (not watch) so a refresh in flight doesn't rebuild this window twice.
    final refresh = ref.read(networkRefreshControllerProvider.notifier);
    return NetworkWindow(
      rows: rows,
      lastReport: refresh.lastReport,
      lastRefreshedAt: refresh.lastFinishedAt,
    );
  }

  /// Adds a library by its published site URL (replaces the old bookmark
  /// add). [url] must pass the [BookmarkUrl] allow-list; [name] is optional —
  /// the descriptor fetch on the next Refresh supplies the real name.
  Future<NetworkAddOutcome> addByUrl({
    required String url,
    String name = '',
  }) async {
    final siteUrl = BookmarkUrl.normalize(url);
    if (siteUrl == null) return NetworkAddOutcome.invalidUrl;
    final repo = await ref.read(networkRepositoryProvider.future);
    final rows = await repo.loadAll();
    if (rows.any((row) => row.siteUrl == siteUrl)) {
      return NetworkAddOutcome.alreadySaved;
    }
    var maxSort = 0;
    for (final row in rows) {
      if (row.sortOrder > maxSort) maxSort = row.sortOrder;
    }
    final result = await repo.upsertBySiteUrl(
      NetworkLibrary(
        siteUrl: siteUrl,
        // §6 name rules for anything the user typed; unusable ⇒ '' (the
        // tile falls back to showing the URL until a fetch names it).
        name: NetworkName.normalizeOrNull(name) ?? '',
        // `source` defaults to `bookmark` — an added-by-URL row is the
        // modern shape of the old bookmark (ADR 0012).
        createdAt: ref.read(clockProvider)(),
        sortOrder: maxSort + 1,
      ),
    );
    if (result.isLeft()) return NetworkAddOutcome.storageFailed;
    ref.invalidateSelf(); // one truth: re-read what the repository stored
    return NetworkAddOutcome.added;
  }

  /// Removes a row. True on success (the window re-reads either way).
  Future<bool> remove(NetworkLibrary row) async {
    final repo = await ref.read(networkRepositoryProvider.future);
    final result = await repo.removeById(row.id);
    if (result.isLeft()) return false;
    ref.invalidateSelf();
    return true;
  }

  /// Records the user's membership decision for the row with [rowId]
  /// (`confirmed` / `declined`, or `pending` for "Reconsider").
  Future<bool> setMembership({
    required int rowId,
    required MembershipState decision,
  }) async {
    final useCase = await ref.read(confirmMembershipUseCaseProvider.future);
    final result = await useCase(rowId: rowId, decision: decision);
    if (result.isLeft()) return false;
    ref.invalidateSelf();
    return true;
  }
}
