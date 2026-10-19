/// The refresh control row of the Libraries tab (presentation,
/// docs/ARCHITECTURE.md §1: user-initiated only).
///
/// Shows the "last refreshed" stamp, an honest one-line summary of the last
/// run's [RefreshReport] (coarse counts only — never URLs or response text,
/// §6), and the Refresh button — which becomes Cancel while a run is in
/// flight. Refresh is the ONLY path that reads other libraries' descriptors,
/// and it is always user-initiated (D11: no background work, ever).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/application/network_refresh_controller.dart';
import 'package:pitaka/features/network/domain/usecases/refresh_network_use_case.dart';

/// Stamp + summary + Refresh/Cancel for the Libraries tab.
class NetworkRefreshBar extends ConsumerWidget {
  /// Creates the bar over the loaded [window].
  const NetworkRefreshBar({required this.window, super.key});

  /// The loaded window (stamp + last report come from it).
  final NetworkWindow window;

  /// "Last refreshed 14:05" (today) / "Last refreshed 2026-10-17 14:05".
  /// [now] is injectable so tests can pin the same-day branch.
  static String stampText(int? lastRefreshedAt, {DateTime? now}) {
    if (lastRefreshedAt == null) return 'Never refreshed yet.';
    final stamp = DateTime.fromMillisecondsSinceEpoch(lastRefreshedAt);
    final today = now ?? DateTime.now();
    final hh = stamp.hour.toString().padLeft(2, '0');
    final mm = stamp.minute.toString().padLeft(2, '0');
    final sameDay =
        stamp.year == today.year &&
        stamp.month == today.month &&
        stamp.day == today.day;
    final date = sameDay
        ? ''
        : '${stamp.year}-'
              '${stamp.month.toString().padLeft(2, '0')}-'
              '${stamp.day.toString().padLeft(2, '0')} ';
    return 'Last refreshed $date$hh:$mm';
  }

  /// One plain sentence per non-zero part of the report.
  static String reportSummary(RefreshReport report) {
    final parts = <String>[
      if (report.fetched > 0) '${report.fetched} up to date',
      if (report.unreachable > 0) '${report.unreachable} unreachable',
      if (report.invalid > 0) '${report.invalid} invalid',
      if (report.schemaTooNew > 0)
        '${report.schemaTooNew} need a newer Pitak version',
      if (report.discovered > 0) '${report.discovered} discovered',
      if (report.conflicts > 0) '${report.conflicts} identity conflicts',
      if (report.pendingMemberships > 0)
        '${report.pendingMemberships} membership questions below',
      if (report.noLongerListed.isNotEmpty)
        '${report.noLongerListed.length} no longer list you',
      if (report.truncated) 'discovery capped at 500 libraries',
    ];
    final body = parts.isEmpty ? 'nothing new' : parts.join(' · ');
    return report.cancelled
        ? 'Cancelled — kept what arrived ($body).'
        : 'Refresh: $body.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refresh = ref.watch(networkRefreshControllerProvider);
    final running = refresh.isLoading;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stampText(window.lastRefreshedAt),
                style: theme.textTheme.bodySmall,
              ),
              if (window.lastReport case final report?)
                Text(
                  reportSummary(report),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (refresh.hasError)
                Text(
                  'Refresh failed — showing your saved list.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (running)
          TextButton.icon(
            onPressed: () =>
                ref.read(networkRefreshControllerProvider.notifier).cancel(),
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: () =>
                ref.read(networkRefreshControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
      ],
    );
  }
}
