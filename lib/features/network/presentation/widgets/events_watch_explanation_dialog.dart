/// The pre-permission explanation for background event alerts (PLAN.md §5,
/// decision 1). Shown once (its version is persisted), BEFORE the Android
/// system prompt, and again only on an explicit enable that needs it.
///
/// Plain language on purpose: what runs, how often, what it costs, what the
/// host can see. On Android < 13 there is no system prompt at all, so this
/// dialog is the only place the user is told.
library;

import 'package:flutter/material.dart';

/// Result of the dialog.
enum EventsWatchExplanationChoice {
  /// Turn alerts on (then request the system permission if needed).
  turnOn,

  /// Keep alerts off for now; the explanation is still acknowledged.
  notNow,
}

/// Shows the explanation. Returns null if dismissed by other means.
Future<EventsWatchExplanationChoice?> showEventsWatchExplanationDialog(
  BuildContext context,
) => showDialog<EventsWatchExplanationChoice>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Event alerts'),
    content: const SingleChildScrollView(
      child: Text(
        'Pitak can tell you when a library you saved posts or changes an '
        'event poster.\n\n'
        'How it works: about every 12 hours, while the app is closed, Pitak '
        "asks each saved library's website for its public events file. "
        "That site then sees your device's connection, like any website "
        'you visit — and that you follow that library.\n\n'
        'This uses a small amount of data, including on mobile networks. '
        "Alerts show the poster's public caption. Whether they appear on "
        "your lock screen follows your phone's lock-screen notification "
        'settings. You can turn this off at any time in Settings.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () =>
            Navigator.of(ctx).pop(EventsWatchExplanationChoice.notNow),
        child: const Text('Not now'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.of(ctx).pop(EventsWatchExplanationChoice.turnOn),
        child: const Text('Turn on'),
      ),
    ],
  ),
);
