import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/local_notifications_notifier.dart';

/// PLAN.md §7 / §8 "UI/privacy": what actually crosses the method channel
/// — generic title when no public name, private lock-screen visibility,
/// the feature tag on every post, and a payload that is only the URL.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The plugin registrant does not run in unit tests; register the Android
  // implementation the way the generated registrant would.
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'areNotificationsEnabled' => true,
            'getNotificationChannels' => <Map<String, Object?>>[],
            'getActiveNotifications' => <Map<String, Object?>>[
              {'id': 5, 'tag': eventsWatchNotificationTag, 'channelId': 'x'},
              {'id': 9, 'tag': 'other_feature', 'channelId': 'x'},
            ],
            _ => null,
          };
        });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const token = WatchSettingsToken(incarnation: 'aaaa', epoch: 1);
  const identity = WatchedLibraryIdentity(
    rowId: 1,
    createdAt: 1,
    siteUrl: 'https://a.github.io/lib/',
  );
  PendingChange change({
    String? caption,
    PendingChangeKind kind = PendingChangeKind.added,
  }) => PendingChange(
    kind: kind,
    identity: identity,
    imageRef: 'posters/a.jpg',
    safeCaption: caption,
    digest: 'a' * 64,
    token: token,
  );

  Map<String, Object?> android(MethodCall call) =>
      ((call.arguments as Map)['platformSpecifics'] as Map)
          .cast<String, Object?>();

  test('showLibrary: generic title without public name, private visibility, '
      'tag + group, URL-only payload', () async {
    final notifier = LocalNotificationsNotifier();

    final result = await notifier.showLibrary(
      LibraryAlert(
        notificationId: 42,
        siteUrl: identity.siteUrl,
        publicName: null,
        changes: [change(caption: 'Book sale Sunday')],
      ),
    );

    expect(result.isRight(), isTrue);
    final show = calls.singleWhere((c) => c.method == 'show');
    final args = show.arguments as Map;
    expect(args['id'], 42);
    expect(args['title'], EventsWatchNotificationText.genericTitle);
    expect(args['body'], 'Book sale Sunday');
    expect(args['payload'], 'site:https://a.github.io/lib/');
    final a = android(show);
    expect(a['tag'], eventsWatchNotificationTag);
    expect(a['groupKey'], eventsWatchGroupKey);
    expect(a['visibility'], isNotNull);
    expect(a['channelId'], eventsWatchChannelId);
    expect(a['setAsGroupSummary'], isFalse);
  });

  test('showLibrary uses the public name when given, and the fixed fallback '
      'line for a null caption', () async {
    await LocalNotificationsNotifier().showLibrary(
      LibraryAlert(
        notificationId: 7,
        siteUrl: identity.siteUrl,
        publicName: 'City Library',
        changes: [change(kind: PendingChangeKind.modified)],
      ),
    );
    final args = calls.single.arguments as Map;
    expect(args['title'], 'City Library');
    expect(args['body'], EventsWatchNotificationText.modifiedFallback);
  });

  test(
    'showSummary posts id 0 as the group summary with the Network payload',
    () async {
      await LocalNotificationsNotifier().showSummary(libraryCount: 3);
      final args = calls.single.arguments as Map;
      expect(args['id'], eventsWatchSummaryNotificationId);
      expect(args['payload'], 'network');
      expect(android(calls.single)['setAsGroupSummary'], isTrue);
      expect(args['title'], contains('3'));
    },
  );

  test(
    'cancelAllFeatureAlerts cancels only notifications carrying our tag',
    () async {
      await LocalNotificationsNotifier().cancelAllFeatureAlerts();
      final cancels = calls.where((c) => c.method == 'cancel').toList();
      expect(cancels.length, 1);
      expect((cancels.single.arguments as Map)['id'], 5);
      expect(
        (cancels.single.arguments as Map)['tag'],
        eventsWatchNotificationTag,
      );
    },
  );

  test(
    'delivery is deliverable when enabled and the channel is absent',
    () async {
      final d = await LocalNotificationsNotifier().delivery();
      expect(d.toNullable(), NotificationDelivery.deliverable);
    },
  );

  test('a platform exception becomes a typed failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'nope');
        });
    final r = await LocalNotificationsNotifier().showSummary(libraryCount: 1);
    expect(r.isLeft(), isTrue);
  });
}
