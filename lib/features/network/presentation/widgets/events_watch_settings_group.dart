/// Settings → Data → **Event alerts** (PLAN.md §7). Pure presentation: it
/// renders `EventsWatchView` and forwards taps to `EventsWatchController`.
///
/// Hidden entirely on platforms without the feature (decision 4). Every
/// phase gets one plain sentence; no URL, label or raw error ever appears.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_controller.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_view.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/presentation/widgets/events_watch_explanation_dialog.dart';
import 'package:pitaka/features/network/presentation/widgets/network_refresh_bar.dart';

/// The Event alerts group of the Data tab.
class EventsWatchSettingsGroup extends ConsumerWidget {
  /// Creates the group.
  const EventsWatchSettingsGroup({super.key});

  /// Helper text for [view]. Static so tests can pin every sentence.
  static String subtitleFor(EventsWatchView view) => switch (view.phase) {
    EventsWatchPhase.unsupported => '',
    EventsWatchPhase.setupOffered || EventsWatchPhase.off =>
      'Get told when a library you saved posts or '
          'changes an event. Checks run about every 12 hours and may use '
          'mobile data.',
    EventsWatchPhase.on =>
      'Checking saved libraries about every 12 hours '
          '(best effort; may use mobile data).',
    EventsWatchPhase.notScheduled =>
      'Checks are not scheduled. Tap Resume '
          'to schedule them again.',
    EventsWatchPhase.noLibraries =>
      'Save a library in Network to get '
          'alerts about its events.',
    EventsWatchPhase.blocked =>
      'Notifications are blocked for Pitak. Allow '
          'them in your system settings, then turn this on again.',
    EventsWatchPhase.updateRequired =>
      'Event alert settings were saved by '
          'a newer version of Pitak. Update the app to use them.',
    EventsWatchPhase.settingsCorrupt =>
      'Event alert settings could not be '
          'read. Reset them to start again.',
    EventsWatchPhase.storageError =>
      'Event alert settings could not be '
          'saved right now. Please try again.',
  };

  /// Status lines under the switch (last check, withheld, recovery).
  static List<String> statusLinesFor(EventsWatchView view, {DateTime? now}) {
    final status = view.status;
    final lines = <String>[];
    final run = status.lastRun;
    if (run != null) {
      if (run.capacityExceeded) {
        lines.add('Too many saved libraries to check; none were checked.');
      } else {
        final stamp = NetworkRefreshBar.stampText(
          run.finishedAt,
          now: now,
        ).replaceFirst('Last refreshed', 'Last check');
        lines.add(
          '$stamp — ${run.checked} checked'
          '${run.withheld > 0 ? ', ${run.withheld} could not be read' : ''}'
          '${run.failed > 0 ? ', ${run.failed} unreachable' : ''}.',
        );
      }
    }
    if (status.pendingAlerts > 0) {
      lines.add('${status.pendingAlerts} alert(s) waiting to be shown.');
    }
    if (status.recoveryNotice == RecoveryNotice.stateReset) {
      lines.add(
        'Earlier alert data could not be read and was reset; any alerts '
        'that were waiting may have been lost.',
      );
    }
    return lines;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(eventsWatchSupportedProvider)) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(eventsWatchControllerProvider);
    final view = async.valueOrNull;
    if (view == null || view.phase == EventsWatchPhase.unsupported) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(eventsWatchControllerProvider.notifier);
    // Debug builds only. The DI provider is the runtime gate; the
    // `if (kDebugMode)` statement makes `_DebugRunAction` unreachable in
    // release, so the AOT compiler drops the class, the provider function,
    // `debugRunNow` and `registerOneOffNow` (verified with
    // `--analyze-size`, 2026-11-08; two inert label literals still appear
    // in the snapshot's string table, with no code that can show them).
    Widget? debugAction;
    if (kDebugMode) debugAction = const _DebugRunAction();
    final theme = Theme.of(context);

    Future<void> onSwitch({required bool on}) async {
      if (!on) return controller.disable();
      if (view.needsExplanation) {
        final choice = await showEventsWatchExplanationDialog(context);
        switch (choice) {
          case EventsWatchExplanationChoice.turnOn:
            return controller.enable();
          case EventsWatchExplanationChoice.notNow:
            return controller.declineOffer();
          case null:
            return;
        }
      }
      return controller.enable();
    }

    // No saved library → nothing to turn on; the subtitle says how to fix
    // it (save a library in Network). The controller refuses too.
    final canToggle = switch (view.phase) {
      EventsWatchPhase.updateRequired ||
      EventsWatchPhase.settingsCorrupt ||
      EventsWatchPhase.noLibraries => false,
      _ => true,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text('Event alerts', style: theme.textTheme.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('Alert me about events at saved libraries'),
          subtitle: Text(subtitleFor(view)),
          value: view.switchOn,
          onChanged: canToggle ? (on) => onSwitch(on: on) : null,
        ),
        for (final line in statusLinesFor(view))
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 4),
            child: Text(line, style: theme.textTheme.bodySmall),
          ),
        if (view.phase == EventsWatchPhase.notScheduled)
          _Action(label: 'Resume', onPressed: controller.resumeScheduling),
        if (view.phase == EventsWatchPhase.storageError)
          _Action(label: 'Try again', onPressed: controller.reconcile),
        if (view.phase == EventsWatchPhase.settingsCorrupt)
          _Action(label: 'Reset event alerts', onPressed: controller.reset),
        if (debugAction != null) debugAction,
        if (view.phase != EventsWatchPhase.settingsCorrupt)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt_outlined),
            title: const Text('Reset event alerts'),
            subtitle: const Text(
              'Turns alerts off, forgets what was already seen, and clears '
              'shown alerts.',
            ),
            onTap: () => _confirmReset(context, controller),
          ),
      ],
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    EventsWatchController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset event alerts?'),
        content: const Text(
          'Alerts will be turned off. The next time you turn them on, Pitak '
          'starts fresh and will not alert you about posters it has already '
          'seen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.reset();
  }
}

/// Debug builds only (see the `kDebugMode` note in the group's `build`).
/// Renders nothing when the DI gate returns null. The worker writes its
/// result to the state file; the status lines refresh on the next
/// reconcile (leave and return).
class _DebugRunAction extends ConsumerWidget {
  const _DebugRunAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(eventsWatchDebugRunNowProvider);
    if (run == null) return const SizedBox.shrink();
    return _Action(
      label: 'Run check now (debug build)',
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final result = await run();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.isRight()
                  ? 'Check enqueued. Leave and return to refresh the status.'
                  : 'Could not enqueue the check.',
            ),
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onPressed});
  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 56),
    child: TextButton(onPressed: onPressed, child: Text(label)),
  );
}
