/// S35 controller tests: the check → auto-start → observe → restart policy,
/// and its fail-safe silence on every error path (an update nag must never
/// become an error surface).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/app_update/application/app_update_controller.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';

import 'fake_app_update_service.dart';

void main() {
  late FakeAppUpdateService service;
  late ProviderContainer container;

  AppUpdateStatus status() => container.read(appUpdateControllerProvider);
  AppUpdateController controller() =>
      container.read(appUpdateControllerProvider.notifier);

  setUp(() {
    service = FakeAppUpdateService();
    container = ProviderContainer(
      overrides: [appUpdateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    addTearDown(service.dispose);
  });

  test('an ineligible install stays silent and never asks the store', () async {
    service.eligible = false;
    expect(status(), AppUpdateStatus.ineligible);
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.ineligible);
    expect(service.checkCalls, 0);
  });

  test('eligible with no update settles on idle', () async {
    expect(
      status(),
      AppUpdateStatus.ineligible,
      reason: 'until the gate answers',
    );
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.idle);
    expect(service.checkCalls, 1);
  });

  test(
    'an available update AUTO-starts the background download (D2)',
    () async {
      service.availability = AppUpdateAvailability.available;
      status();
      await pumpEventQueue();
      expect(status(), AppUpdateStatus.downloading);
      expect(service.startCalls, 1);
    },
  );

  test('a refused download start degrades to silence', () async {
    service
      ..availability = AppUpdateAvailability.available
      ..startResult = false;
    status();
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.idle);
  });

  test('an already-running download resumes without re-starting', () async {
    service.availability = AppUpdateAvailability.inProgress;
    status();
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.downloading);
    expect(service.startCalls, 0);
  });

  test('a finished download offers the restart', () async {
    service.availability = AppUpdateAvailability.downloaded;
    status();
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.downloaded);
    await controller().restartToUpdate();
    expect(service.completeCalls, 1);
  });

  test('install-state stream events drive the status', () async {
    status();
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.idle);
    service.emit(AppUpdateStatus.downloading);
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.downloading);
    service.emit(AppUpdateStatus.downloaded);
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.downloaded);
  });

  test(
    'dismiss hides the banner for the session, ignoring later events',
    () async {
      service.availability = AppUpdateAvailability.available;
      status();
      await pumpEventQueue();
      expect(status(), AppUpdateStatus.downloading);
      controller().dismiss();
      expect(status(), AppUpdateStatus.idle);
      service.emit(AppUpdateStatus.downloaded);
      await pumpEventQueue();
      expect(status(), AppUpdateStatus.idle, reason: 'dismissal is respected');
    },
  );

  test('a throwing check degrades to idle (fail safe)', () async {
    service.throwOnCheck = Exception('play store exploded');
    status();
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.idle);
  });

  test('a throwing completeUpdate degrades to idle', () async {
    service
      ..availability = AppUpdateAvailability.downloaded
      ..throwOnComplete = Exception('nope');
    status();
    await pumpEventQueue();
    expect(status(), AppUpdateStatus.downloaded);
    await controller().restartToUpdate();
    expect(status(), AppUpdateStatus.idle);
  });
}
