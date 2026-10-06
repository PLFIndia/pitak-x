/// S35: the pure mapping layer of [PlayAppUpdateService] — Play's check
/// result onto the flow's decisions, and Play's install states onto the
/// banner's coarse statuses. The mappings are `@visibleForTesting` statics
/// precisely so they are testable without a method channel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/app_update/infrastructure/play_app_update_service.dart';

AppUpdateInfo _info({
  UpdateAvailability availability = UpdateAvailability.updateNotAvailable,
  bool flexibleAllowed = false,
  InstallStatus installStatus = InstallStatus.unknown,
}) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: false,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: flexibleAllowed,
  flexibleAllowedPreconditions: null,
  availableVersionCode: null,
  installStatus: installStatus,
  packageName: 'dev.khoj.pitaka',
  clientVersionStalenessDays: null,
  updatePriority: 0,
);

void main() {
  group('availabilityFrom', () {
    test('updateAvailable + flexible allowed → available', () {
      expect(
        PlayAppUpdateService.availabilityFrom(
          _info(
            availability: UpdateAvailability.updateAvailable,
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
            _info(availability: UpdateAvailability.updateAvailable),
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
            _info(
              availability:
                  UpdateAvailability.developerTriggeredUpdateInProgress,
              installStatus: InstallStatus.downloading,
            ),
          ),
          AppUpdateAvailability.inProgress,
        );
      },
    );

    test('a developer-triggered download already finished → downloaded', () {
      expect(
        PlayAppUpdateService.availabilityFrom(
          _info(
            availability: UpdateAvailability.developerTriggeredUpdateInProgress,
            installStatus: InstallStatus.downloaded,
          ),
        ),
        AppUpdateAvailability.downloaded,
      );
    });

    test('not available / unknown → none', () {
      expect(
        PlayAppUpdateService.availabilityFrom(_info()),
        AppUpdateAvailability.none,
      );
      expect(
        PlayAppUpdateService.availabilityFrom(
          _info(availability: UpdateAvailability.unknown),
        ),
        AppUpdateAvailability.none,
      );
    });
  });

  group('statusFromInstall', () {
    test('pending / downloading / installing → downloading', () {
      for (final s in [
        InstallStatus.pending,
        InstallStatus.downloading,
        InstallStatus.installing,
      ]) {
        expect(
          PlayAppUpdateService.statusFromInstall(s),
          AppUpdateStatus.downloading,
          reason: '$s',
        );
      }
    });

    test('downloaded → downloaded', () {
      expect(
        PlayAppUpdateService.statusFromInstall(InstallStatus.downloaded),
        AppUpdateStatus.downloaded,
      );
    });

    test('installed / failed / canceled / unknown → idle (silence)', () {
      for (final s in [
        InstallStatus.installed,
        InstallStatus.failed,
        InstallStatus.canceled,
        InstallStatus.unknown,
      ]) {
        expect(
          PlayAppUpdateService.statusFromInstall(s),
          AppUpdateStatus.idle,
          reason: '$s',
        );
      }
    });
  });
}
