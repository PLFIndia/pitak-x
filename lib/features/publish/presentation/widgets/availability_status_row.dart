/// The availability lane's status on Publish → Connection, with **Update
/// availability now** and the one-time notice (presentation; ADR 0019, plan
/// C.4 status table and C.8).
///
/// Pure presentation: it renders the lane's [AvailabilityLaneView] and
/// forwards the two taps to the notifier. The sentences are the plan's
/// drafts; plan S8 sets the final words together with the guide copy.
///
/// Shown only when this build runs the lane (`availabilityLaneActivated`,
/// false until plan S8): watching the lane's provider is what starts it, so
/// the row must not even be built before then.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/local_time_text.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/presentation/widgets/section_card.dart';

/// The one-time notice (plan C.8).
const String availabilityNoticeText =
    'Availability now updates by itself after lending. You can turn this off '
    'in Settings.';

/// The status sentence for [status]. [now] is the current time and [time]
/// formats an epoch-millisecond time for the user; both are passed in so the
/// wording is testable without a clock or a locale.
String availabilityStatusText(
  AvailabilityLaneStatus status, {
  required int now,
  required String Function(int millis) time,
}) => switch (status) {
  AvailabilityLaneStarting() => 'Checking availability updates…',
  AvailabilityLaneOff() =>
    'Availability updates are off. Turn them on in Settings.',
  AvailabilityLaneNotReady(:final reason) => reason,
  AvailabilityLaneScheduled(:final at, :final gitHubMayDelay) => [
    if (at - now <= _soon.inMilliseconds)
      'Availability will update in a moment.'
    else
      'Availability will update at ${time(at)}.',
    if (gitHubMayDelay) 'GitHub may delay this update.',
  ].join(' '),
  AvailabilityLanePublishing() => 'Updating availability…',
  AvailabilityLaneGoingLive(:final asOf) =>
    'Availability updated ${time(asOf)} · going live',
  AvailabilityLaneUpToDate(:final asOf) => 'Availability updated ${time(asOf)}',
  AvailabilityLanePending(:final reason, :final retryAt) =>
    retryAt == null ? reason : '$reason Next try at ${time(retryAt)}.',
};

/// "In a moment" covers the 20 s debounce and a little more.
const Duration _soon = Duration(minutes: 1);

/// The availability section of the publish hub.
class AvailabilityStatusRow extends ConsumerWidget {
  /// Creates the row.
  const AvailabilityStatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(availabilityAutoPublisherProvider);
    final status = view.status;
    final now = ref.watch(clockProvider)();
    final canPublish = switch (status) {
      AvailabilityLaneStarting() ||
      AvailabilityLaneOff() ||
      AvailabilityLanePublishing() => false,
      _ => true,
    };
    return SectionCard(
      title: 'Availability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (view.noticeDue) ...[
            _Notice(
              onDismiss: () => ref
                  .read(availabilityAutoPublisherProvider.notifier)
                  .dismissNotice(),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            availabilityStatusText(
              status,
              now: now,
              time: (millis) =>
                  formatLocalMoment(context, millis, nowMillis: now),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: canPublish
                ? () => ref
                      .read(availabilityAutoPublisherProvider.notifier)
                      .publishNow()
                : null,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Update availability now'),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                availabilityNoticeText,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(onPressed: onDismiss, child: const Text('OK')),
          ],
        ),
      ),
    );
  }
}
