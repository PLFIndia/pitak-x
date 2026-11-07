/// `flutter_local_notifications` adapter of `LocalNotifier` (PLAN.md §4,
/// §7). Verified against plugin 20.1.0 (Step 0, 2026-11-07).
///
/// Privacy rules enforced here (beginner note):
///  - The title is the library's public name ONLY when the caller passes
///    one (the source sets it only for descriptor-confirmed rows); otherwise
///    a generic title. A user-typed label can never reach this class.
///  - `visibility: private` hides the content on a secure lock screen.
///  - The payload is the canonical site URL and nothing else; the tap
///    handler re-validates it against the saved rows before navigating.
///  - Every notification carries the feature's tag and group key, so
///    `cancelAllFeatureAlerts` can remove exactly ours and nothing else.
///
/// "Submitted" means `notify()` returned (`FlutterLocalNotificationsPlugin
/// .java:1296-1304`); display is the OS's decision.
library;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_payload.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';

/// Stable channel id. Changing it creates a second channel for users.
const String eventsWatchChannelId = 'pitak_events_watch';

/// Feature tag on every notification; the scope of feature-wide cancels.
const String eventsWatchNotificationTag = 'pitak_events_watch';

/// Group key for the summary + children.
const String eventsWatchGroupKey = 'dev.khoj.pitaka.events_watch';

/// Reserved summary notification id (PLAN.md §4).
const int eventsWatchSummaryNotificationId = 0;

/// Drawable name of the status-bar icon (kept by `res/raw/keep.xml`).
const String eventsWatchSmallIcon = 'ic_stat_pitak_events';

/// User-facing strings. English only (the app has no l10n).
abstract final class EventsWatchNotificationText {
  /// Channel name shown in system settings.
  static const String channelName = 'Event alerts';

  /// Channel description shown in system settings.
  static const String channelDescription =
      'New or changed event posters at libraries you saved.';

  /// Generic title when no public name is available (decision 13).
  static const String genericTitle = 'New event at a saved library';

  /// Body line for a poster without a safe caption.
  static const String captionFallback = 'A library you saved posted an event.';

  /// Body line for a modified poster without a safe caption.
  static const String modifiedFallback =
      'A library you saved updated an event.';

  /// Summary text; `%d` is the library count.
  static String summary(int count) => count == 1
      ? 'New events at 1 saved library'
      : 'New events at $count saved libraries';
}

/// See the file header.
final class LocalNotificationsNotifier implements LocalNotifier {
  /// Creates the adapter over [plugin] (the singleton in production, a
  /// mock in tests).
  LocalNotificationsNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Registers the icon and the tap callback. Must run once in BOTH the
  /// foreground and the worker isolate before any other call.
  Future<Either<Failure, Unit>> initialize({
    void Function(String? payload)? onTap,
  }) => _guard(() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(eventsWatchSmallIcon),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) => onTap(response.payload),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        eventsWatchChannelId,
        EventsWatchNotificationText.channelName,
        description: EventsWatchNotificationText.channelDescription,
      ),
    );
    return right(unit);
  });

  /// The payload of the notification that launched the app, if any.
  Future<Either<Failure, String?>> launchPayload() => _guard(() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) {
      return right(null);
    }
    return right(details.notificationResponse?.payload);
  });

  /// Android 13+ runtime prompt. Pre-33 returns granted without a dialog;
  /// callers must not read that as consent (PLAN.md privacy notes).
  Future<Either<Failure, NotificationPermissionOutcome>> requestPermission() =>
      _guard(() async {
        final android = _android;
        if (android == null) {
          return right(NotificationPermissionOutcome.permanentlyDenied);
        }
        final granted = await android.requestNotificationsPermission();
        if (granted ?? false) {
          return right(NotificationPermissionOutcome.granted);
        }
        // The plugin cannot distinguish "denied now" from "never ask again";
        // a denial is reported as denied and the controller persists OFF.
        return right(NotificationPermissionOutcome.denied);
      });

  @override
  Future<Either<Failure, NotificationDelivery>> delivery() => _guard(() async {
    final android = _android;
    if (android == null) return right(NotificationDelivery.blocked);
    final appEnabled = await android.areNotificationsEnabled() ?? false;
    if (!appEnabled) return right(NotificationDelivery.blocked);
    final channels = await android.getNotificationChannels();
    // Before the first show the channel may not exist yet: that is not a
    // block. Once it exists, importance `none` means the user blocked it.
    for (final channel in channels ?? const <AndroidNotificationChannel>[]) {
      if (channel.id == eventsWatchChannelId &&
          channel.importance == Importance.none) {
        return right(NotificationDelivery.blocked);
      }
    }
    return right(NotificationDelivery.deliverable);
  });

  @override
  Future<Either<Failure, Unit>> showLibrary(LibraryAlert alert) => _guard(
    () async {
      final lines = [for (final c in alert.changes) _lineFor(c)];
      await _plugin.show(
        id: alert.notificationId,
        title: alert.publicName ?? EventsWatchNotificationText.genericTitle,
        body: lines.first,
        payload: EventsWatchPayload.library(alert.siteUrl),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            eventsWatchChannelId,
            EventsWatchNotificationText.channelName,
            channelDescription: EventsWatchNotificationText.channelDescription,
            icon: eventsWatchSmallIcon,
            tag: eventsWatchNotificationTag,
            groupKey: eventsWatchGroupKey,
            visibility: NotificationVisibility.private,
            category: AndroidNotificationCategory.event,
            styleInformation: lines.length > 1
                ? InboxStyleInformation(lines)
                : BigTextStyleInformation(lines.first),
          ),
        ),
      );
      return right(unit);
    },
  );

  @override
  Future<Either<Failure, Unit>> showSummary({required int libraryCount}) =>
      _guard(() async {
        await _plugin.show(
          id: eventsWatchSummaryNotificationId,
          title: EventsWatchNotificationText.summary(libraryCount),
          payload: EventsWatchPayload.network,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              eventsWatchChannelId,
              EventsWatchNotificationText.channelName,
              channelDescription:
                  EventsWatchNotificationText.channelDescription,
              icon: eventsWatchSmallIcon,
              tag: eventsWatchNotificationTag,
              groupKey: eventsWatchGroupKey,
              setAsGroupSummary: true,
              visibility: NotificationVisibility.private,
              category: AndroidNotificationCategory.event,
            ),
          ),
        );
        return right(unit);
      });

  @override
  Future<Either<Failure, Unit>> cancelLibrary(int notificationId) => _guard(
    () async {
      await _plugin.cancel(id: notificationId, tag: eventsWatchNotificationTag);
      return right(unit);
    },
  );

  @override
  Future<Either<Failure, Unit>> cancelAllFeatureAlerts() => _guard(() async {
    // Only notifications carrying OUR tag are touched. Active ones are
    // enumerated (API 23+) so nothing of another feature is cancelled.
    final android = _android;
    if (android == null) return right(unit);
    final active = await android.getActiveNotifications();
    for (final n in active) {
      if (n.tag == eventsWatchNotificationTag && n.id != null) {
        await _plugin.cancel(id: n.id!, tag: eventsWatchNotificationTag);
      }
    }
    return right(unit);
  });

  static String _lineFor(PendingChange change) {
    final caption = change.safeCaption;
    if (caption != null) return caption;
    return switch (change.kind) {
      PendingChangeKind.added => EventsWatchNotificationText.captionFallback,
      PendingChangeKind.modified =>
        EventsWatchNotificationText.modifiedFallback,
    };
  }

  Future<Either<Failure, T>> _guard<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      return left(UnexpectedFailure('notifier platform ${e.code}'));
    } on MissingPluginException {
      return left(const UnexpectedFailure('notifier plugin missing'));
    }
  }
}
