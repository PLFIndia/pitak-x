/// S35: the pure eligibility rule — the Play update flow may run ONLY on an
/// Android install of the play-flavor applicationId; everything else (the
/// fdroid flavor, iOS, desktop, tests, an unknown identity) fails safe to
/// "feature off".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';

void main() {
  group('AppUpdatePolicy.isPlayInstall', () {
    test('Android + the play applicationId is eligible', () {
      expect(
        AppUpdatePolicy.isPlayInstall(
          isAndroid: true,
          applicationId: AppUpdatePolicy.playApplicationId,
        ),
        isTrue,
      );
    });

    test('the fdroid flavor is NOT eligible', () {
      expect(
        AppUpdatePolicy.isPlayInstall(
          isAndroid: true,
          applicationId: 'dev.khoj.pitaka.fdroid',
        ),
        isFalse,
      );
    });

    test('non-Android is never eligible, whatever the id', () {
      expect(
        AppUpdatePolicy.isPlayInstall(
          isAndroid: false,
          applicationId: AppUpdatePolicy.playApplicationId,
        ),
        isFalse,
      );
    });

    test('an unknown applicationId fails safe to not eligible', () {
      expect(
        AppUpdatePolicy.isPlayInstall(isAndroid: true, applicationId: null),
        isFalse,
      );
    });
  });
}
