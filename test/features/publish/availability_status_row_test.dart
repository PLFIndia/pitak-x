import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/application/availability/availability_publish_result.dart';
import 'package:pitaka/features/publish/presentation/widgets/availability_status_row.dart';

/// The availability status row on Publish → Connection (plan C.4 status
/// table, C.8): every status reads as a fixed sentence, the button and the
/// notice reach the lane, in light and dark themes.
void main() {
  // 2:05 pm local time on the day of `now`.
  final now = DateTime(2026, 11, 2, 14, 5).millisecondsSinceEpoch;
  String time(int millis) => 'T${(millis - now) ~/ 60000}';

  group('availabilityStatusText', () {
    String text(AvailabilityLaneStatus status) =>
        availabilityStatusText(status, now: now, time: time);

    test('every status has its sentence', () {
      expect(
        text(const AvailabilityLaneStarting()),
        'Checking availability updates…',
      );
      expect(
        text(const AvailabilityLaneOff()),
        'Availability updates are off. Turn them on in Settings → Data.',
      );
      expect(
        text(
          const AvailabilityLaneNotReady(
            AvailabilityPublishMessages.catalogueNotKeyed,
          ),
        ),
        AvailabilityPublishMessages.catalogueNotKeyed,
      );
      expect(
        text(const AvailabilityLanePublishing()),
        'Updating availability…',
      );
      expect(
        text(AvailabilityLaneGoingLive(now)),
        'Availability updated T0 · going live',
      );
      expect(
        text(AvailabilityLaneUpToDate(now - 60000)),
        'Availability updated T-1',
      );
    });

    test('scheduled: "in a moment" within a minute, else the time', () {
      expect(
        text(AvailabilityLaneScheduled(now + 20000)),
        'Availability will update in a moment.',
      );
      expect(
        text(AvailabilityLaneScheduled(now + 6 * 60000)),
        'Availability will update at T6.',
      );
      expect(
        text(AvailabilityLaneScheduled(now, gitHubMayDelay: true)),
        'Availability will update in a moment. GitHub may delay this update.',
      );
    });

    test(
      'the final words (plan S8, A.6 #80) name places the user can find',
      () {
        // The switch lives in Settings → Data (PublishingSettingsGroup), the
        // vault in the drawer as "Borrowers vault", and the card above this row
        // has the button "Publish catalogue now".
        expect(
          availabilityNoticeText,
          'Availability now updates by itself after you lend or return an '
          'item. You can turn this off in Settings → Data.',
        );
        expect(
          AvailabilityPublishMessages.catalogueNotKeyed,
          'Tap Publish catalogue now once; after that, availability updates '
          'by itself.',
        );
        expect(
          AvailabilityPublishMessages.repairSite,
          'Your site needs a full publish: tap Publish catalogue now and '
          'review the replacement.',
        );
        expect(
          AvailabilityLaneMessages.unlockVault,
          'Unlock the Borrowers vault once so Pitak can see what is lent out.',
        );
      },
    );

    test('pending: the reason, and the next try when known', () {
      expect(
        text(const AvailabilityLanePending('No connection.')),
        'No connection.',
      );
      expect(
        text(AvailabilityLanePending('No connection.', retryAt: now + 120000)),
        'No connection. Next try at T2.',
      );
    });
  });

  group('the row', () {
    Future<_FakeLane> pump(
      WidgetTester tester,
      AvailabilityLaneView view, {
      ThemeData? theme,
    }) async {
      final lane = _FakeLane(view);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availabilityAutoPublisherProvider.overrideWith(() => lane),
            clockProvider.overrideWithValue(() => now),
          ],
          child: MaterialApp(
            theme: theme ?? AppTheme.light,
            home: const Scaffold(body: AvailabilityStatusRow()),
          ),
        ),
      );
      return lane;
    }

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('shows the status and sends the tap ($name)', (tester) async {
        final lane = await pump(
          tester,
          AvailabilityLaneView(status: AvailabilityLaneUpToDate(now)),
          theme: theme,
        );

        expect(find.text('Availability'), findsOneWidget);
        expect(find.textContaining('Availability updated'), findsOneWidget);
        expect(find.textContaining('2:05'), findsOneWidget);
        await tester.tap(find.text('Update availability now'));
        await tester.pump();
        expect(lane.publishNowCalls, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the one-time notice is dismissed through the lane ($name)', (
        tester,
      ) async {
        final lane = await pump(
          tester,
          AvailabilityLaneView(
            status: AvailabilityLaneScheduled(now + 20000),
            noticeDue: true,
          ),
          theme: theme,
        );

        expect(find.text(availabilityNoticeText), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pump();
        expect(lane.dismissCalls, 1);
      });
    }

    testWidgets('the button is off while off, starting or publishing', (
      tester,
    ) async {
      for (final status in const [
        AvailabilityLaneOff(),
        AvailabilityLaneStarting(),
        AvailabilityLanePublishing(),
      ]) {
        final lane = await pump(tester, AvailabilityLaneView(status: status));
        await tester.tap(find.text('Update availability now'));
        await tester.pump();
        expect(lane.publishNowCalls, 0, reason: '$status');
      }
    });

    testWidgets('a time on an earlier day carries its date', (tester) async {
      await pump(
        tester,
        AvailabilityLaneView(
          status: AvailabilityLaneUpToDate(
            now - const Duration(days: 2).inMilliseconds,
          ),
        ),
      );
      expect(find.textContaining('Oct 31'), findsOneWidget);
    });
  });
}

class _FakeLane extends AvailabilityAutoPublisher {
  _FakeLane(this.view);

  final AvailabilityLaneView view;
  int publishNowCalls = 0;
  int dismissCalls = 0;

  @override
  AvailabilityLaneView build() => view;

  @override
  Future<void> publishNow() async => publishNowCalls++;

  @override
  Future<void> dismissNotice() async => dismissCalls++;
}
