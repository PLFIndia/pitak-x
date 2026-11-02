import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/availability/availability_auto_publisher.dart';
import 'package:pitaka/features/publish/application/availability/availability_lane_status.dart';
import 'package:pitaka/features/publish/presentation/widgets/availability_lifecycle_relay.dart';

/// The relay forwards app resumes to the lane (plan C.4 "Retry triggers"),
/// and does nothing — not even start the lane — in a build whose kill switch
/// is off (plan A.6 #77).
void main() {
  Future<_CountingLane> pump(
    WidgetTester tester, {
    required bool activated,
  }) async {
    final lane = _CountingLane();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          availabilityLaneActivatedProvider.overrideWithValue(activated),
          availabilityAutoPublisherProvider.overrideWith(() => lane),
        ],
        child: const AvailabilityLifecycleRelay(
          child: MaterialApp(home: Text('app')),
        ),
      ),
    );
    return lane;
  }

  testWidgets('a resume reaches the lane; other states do not', (tester) async {
    final lane = await pump(tester, activated: true);
    expect(find.text('app'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(lane.resumes, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(lane.resumes, 1);
  });

  testWidgets('with the kill switch off nothing is forwarded or started', (
    tester,
  ) async {
    final lane = await pump(tester, activated: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(lane.resumes, 0);
    expect(lane.built, isFalse, reason: 'the lane provider was never read');
  });
}

class _CountingLane extends AvailabilityAutoPublisher {
  int resumes = 0;
  bool built = false;

  @override
  AvailabilityLaneView build() {
    built = true;
    return AvailabilityLaneView.starting;
  }

  @override
  Future<void> resumed() async => resumes++;
}
