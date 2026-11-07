/// The reconcile step of a background run (PLAN.md §1 token/generation
/// rules, §2 pruning). Pure: takes the latest state plus what the run
/// observed and returns the next state. No IO.
library;

import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/notification_id_allocator.dart';
import 'package:pitaka/features/network/domain/events_watch/site_watch_status.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// Applies token, generation and membership rules to [latest].
///
/// Notification ids of removed/reset sites are appended to
/// [removedNotificationIds] so the caller can cancel them after the commit.
EventsWatchState reconcileWatchState(
  EventsWatchState latest, {
  required WatchSettingsToken token,
  required String generation,
  required List<WatchedLibrary> libraries,
  required List<int> removedNotificationIds,
}) {
  final observed = latest.observedToken;
  final tokenChanged = observed == null || !observed.sameAs(token);
  final incarnationChanged =
      observed == null || !observed.sameIncarnation(token);
  final generationChanged = latest.generation != generation;

  var sites = latest.sites;
  var pending = latest.pending;

  if (generationChanged) {
    removedNotificationIds.addAll(
      sites.map((s) => s.notificationId).whereType<int>(),
    );
    sites = const [];
    pending = const [];
  } else {
    if (tokenChanged) pending = const [];
    if (incarnationChanged) {
      sites = [for (final s in sites) s.copyWith(clearBaseline: true)];
    }
  }

  // Prune rows no longer saved (full identity, not URL membership).
  final current = {for (final l in libraries) l.siteUrl: l.identity};
  final kept = <SiteWatchStatus>[];
  for (final site in sites) {
    final identity = current[site.siteUrl];
    if (identity != null && identity.sameAs(site.identity)) {
      kept.add(site);
    } else if (site.notificationId != null) {
      removedNotificationIds.add(site.notificationId!);
    }
  }
  final keptUrls = kept.map((s) => s.siteUrl).toSet();
  pending = [
    for (final p in pending)
      if (keptUrls.contains(p.siteUrl)) p,
  ];

  // Add fresh statuses for new rows; allocate ids where missing.
  final taken = kept.map((s) => s.notificationId).whereType<int>().toSet();
  final byUrl = {for (final s in kept) s.siteUrl: s};
  final result = <SiteWatchStatus>[];
  final urls = libraries.map((l) => l.siteUrl).toList()..sort();
  for (final url in urls) {
    var site = byUrl[url] ?? SiteWatchStatus.fresh(current[url]!);
    if (site.notificationId == null) {
      final id = NotificationIdAllocator.allocate(url, taken: taken);
      taken.add(id);
      site = site.copyWith(notificationId: id);
    }
    result.add(site);
  }

  return latest.copyWith(
    observedToken: token,
    generation: generation,
    sites: result,
    pending: pending,
    // A superseded marker (different token) is cleared on an enabled run.
    clearRevocationToken: true,
    // Recovery notices clear only on a token change (PLAN.md §6).
    clearRecoveryNotice: tokenChanged,
  );
}
