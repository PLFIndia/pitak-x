/// S35/S36: [PlayAppUpdateService] — the pure mapping layer (Play's check
/// result onto the flow's decisions, Play's install states onto the banner's
/// coarse statuses) AND the channel boundary. The boundary tests script the
/// `dev.khoj.pitaka/app_update` channels exactly as the play-flavor Kotlin
/// (`AppUpdateChannel.kt`) answers, plus the hostile cases: no native handler
/// at all (which IS the fdroid flavor), platform errors, malformed replies.
/// Every one of those must degrade to the safe negative — the service may
/// only ever go silent, never throw.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/app_info.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/infrastructure/play_app_update_service.dart';

final class _StubAppInfo implements AppInfo {
  const _StubAppInfo();
  @override
  Future<String?> applicationId() async => 'dev.khoj.pitaka';
}

PlayUpdateCheck _check({
  int availability = PlayUpdateAvailability.updateNotAvailable,
  bool flexibleAllowed = false,
  int installStatus = PlayInstallStatus.unknown,
}) => PlayUpdateCheck(
  updateAvailability: availability,
  flexibleAllowed: flexibleAllowed,
  installStatus: installStatus,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('availabilityFrom', () {
    test('updateAvailable + flexible allowed → available', () {
      expect(
        PlayAppUpdateService.availabilityFrom(
          _check(
            availability: PlayUpdateAvailability.updateAvailable,
            flexibleAllowed: true,
          ),
        ),
        AppUpdateAvailability.available,
      );
    });

    test(
      'an immediate-only update → none (this app ships flexible only, D2)',
      () {
        expect(
          PlayAppUpdateService.availabilityFrom(
            _check(availability: PlayUpdateAvailability.updateAvailable),
          ),
          AppUpdateAvailability.none,
        );
      },
    );

    test(
      'a developer-triggered download in progress → inProgress (resume)',
      () {
        expect(
          PlayAppUpdateService.availabilityFrom(
            _check(
              availability:
                  PlayUpdateAvailability.developerTriggeredUpdateInProgress,
              installStatus: PlayInstallStatus.downloading,
            ),
          ),
          AppUpdateAvailability.inProgress,
        );
      },
    );

    test('a developer-triggered download already finished → downloaded', () {
      expect(
        PlayAppUpdateService.availabilityFrom(
          _check(
            availability:
                PlayUpdateAvailability.developerTriggeredUpdateInProgress,
            installStatus: PlayInstallStatus.downloaded,
          ),
        ),
        AppUpdateAvailability.downloaded,
      );
    });

    test('not available / unknown / undocumented code → none', () {
      for (final code in [
        PlayUpdateAvailability.updateNotAvailable,
        PlayUpdateAvailability.unknown,
        42,
        -1,
      ]) {
        expect(
          PlayAppUpdateService.availabilityFrom(
            _check(availability: code, flexibleAllowed: true),
          ),
          AppUpdateAvailability.none,
          reason: 'code $code',
        );
      }
    });
  });

  group('statusFromInstall', () {
    test('pending / downloading / installing → downloading', () {
      for (final s in [
        PlayInstallStatus.pending,
        PlayInstallStatus.downloading,
        PlayInstallStatus.installing,
      ]) {
        expect(
          PlayAppUpdateService.statusFromInstall(s),
          AppUpdateStatus.downloading,
          reason: 'status $s',
        );
      }
    });

    test('downloaded → downloaded', () {
      expect(
        PlayAppUpdateService.statusFromInstall(PlayInstallStatus.downloaded),
        AppUpdateStatus.downloaded,
      );
    });

    test('installed / failed / canceled / unknown / undocumented → idle', () {
      for (final s in [
        PlayInstallStatus.installed,
        PlayInstallStatus.failed,
        PlayInstallStatus.canceled,
        PlayInstallStatus.unknown,
        99,
      ]) {
        expect(
          PlayAppUpdateService.statusFromInstall(s),
          AppUpdateStatus.idle,
          reason: 'status $s',
        );
      }
    });
  });

  group('PlayUpdateCheck.fromChannel (boundary validation)', () {
    test('accepts the exact shape the Kotlin side sends', () {
      final parsed = PlayUpdateCheck.fromChannel(<Object?, Object?>{
        'updateAvailability': 2,
        'flexibleAllowed': true,
        'installStatus': 0,
      });
      expect(parsed, isNotNull);
      expect(
        parsed!.updateAvailability,
        PlayUpdateAvailability.updateAvailable,
      );
      expect(parsed.flexibleAllowed, isTrue);
      expect(parsed.installStatus, PlayInstallStatus.unknown);
    });

    test('rejects null, non-map, missing keys and wrong types', () {
      final hostile = <Object?>[
        null,
        'nope',
        42,
        <Object?>[2, true, 0],
        <Object?, Object?>{},
        <Object?, Object?>{'updateAvailability': 2, 'flexibleAllowed': true},
        <Object?, Object?>{
          'updateAvailability': '2',
          'flexibleAllowed': true,
          'installStatus': 0,
        },
        <Object?, Object?>{
          'updateAvailability': 2,
          'flexibleAllowed': 1,
          'installStatus': 0,
        },
        <Object?, Object?>{
          'updateAvailability': 2,
          'flexibleAllowed': true,
          'installStatus': null,
        },
      ];
      for (final input in hostile) {
        expect(
          PlayUpdateCheck.fromChannel(input),
          isNull,
          reason: 'input $input',
        );
      }
    });
  });

  group('channel boundary', () {
    const service = PlayAppUpdateService(appInfo: _StubAppInfo());
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];

    void script(Future<Object?> Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(PlayAppUpdateService.methodChannel, (
        call,
      ) {
        calls.add(call.method);
        return handler(call);
      });
    }

    setUp(calls.clear);
    tearDown(() {
      messenger
        ..setMockMethodCallHandler(PlayAppUpdateService.methodChannel, null)
        ..setMockStreamHandler(PlayAppUpdateService.eventChannel, null);
    });

    test(
      'no native handler (= fdroid flavor) → check none, start false',
      () async {
        // Nothing scripted: the channel has no handler, exactly like the
        // fdroid flavor's inert AppUpdateChannel.
        expect(await service.check(), AppUpdateAvailability.none);
        expect(await service.startFlexibleDownload(), isFalse);
      },
    );

    test('checkForUpdate happy path → available, no arguments sent', () async {
      script((call) async {
        expect(call.arguments, isNull);
        return <Object?, Object?>{
          'updateAvailability': PlayUpdateAvailability.updateAvailable,
          'flexibleAllowed': true,
          'installStatus': PlayInstallStatus.unknown,
        };
      });
      expect(await service.check(), AppUpdateAvailability.available);
      expect(calls, ['checkForUpdate']);
    });

    test('checkForUpdate PlatformException (no Play Store) → none', () async {
      script(
        (_) async =>
            throw PlatformException(code: 'TASK_FAILURE', message: 'x'),
      );
      expect(await service.check(), AppUpdateAvailability.none);
    });

    test('checkForUpdate malformed reply → none', () async {
      script((_) async => <Object?, Object?>{'updateAvailability': 'yes'});
      expect(await service.check(), AppUpdateAvailability.none);
    });

    test('startFlexibleUpdate accepted → true', () async {
      script((_) async => null);
      expect(await service.startFlexibleDownload(), isTrue);
      expect(calls, ['startFlexibleUpdate']);
    });

    test('startFlexibleUpdate refused by the user → false', () async {
      script((_) async => throw PlatformException(code: 'USER_DENIED_UPDATE'));
      expect(await service.startFlexibleDownload(), isFalse);
    });

    test('completeUpdate forwards to the native side', () async {
      script((_) async => null);
      await service.completeUpdate();
      expect(calls, ['completeFlexibleUpdate']);
    });

    test('completeUpdate with no handler throws (controller catches it)', () {
      expect(service.completeUpdate(), throwsA(isA<MissingPluginException>()));
    });

    test(
      'statusChanges maps the raw install-state ints, non-ints → idle',
      () async {
        messenger.setMockStreamHandler(
          PlayAppUpdateService.eventChannel,
          MockStreamHandler.inline(
            onListen: (_, events) {
              events
                ..success(PlayInstallStatus.pending)
                ..success(PlayInstallStatus.downloading)
                ..success('garbage')
                ..success(PlayInstallStatus.downloaded)
                ..success(PlayInstallStatus.installed)
                ..endOfStream();
            },
          ),
        );
        expect(await service.statusChanges.toList(), [
          AppUpdateStatus.downloading,
          AppUpdateStatus.downloading,
          AppUpdateStatus.idle,
          AppUpdateStatus.downloaded,
          AppUpdateStatus.idle,
        ]);
      },
    );
  });
}
