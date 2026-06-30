import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/settings/presentation/pages/settings_page.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';

void main() {
  group('evaluateAppLockToggle', () {
    test('disabling never authenticates and always succeeds', () async {
      var prompted = false;
      final out = await evaluateAppLockToggle(
        enabled: false,
        availability: BiometricAvailability.unavailable,
        authenticate: () async {
          prompted = true;
          return true;
        },
      );
      expect(out, AppLockToggleOutcome.disable);
      expect(prompted, isFalse);
    });

    test('enabling requires a successful prompt', () async {
      var prompted = false;
      final out = await evaluateAppLockToggle(
        enabled: true,
        availability: BiometricAvailability.available,
        authenticate: () async {
          prompted = true;
          return true;
        },
      );
      expect(out, AppLockToggleOutcome.enable);
      expect(prompted, isTrue);
    });

    test('enabling stays OFF when the prompt fails/cancels', () async {
      final out = await evaluateAppLockToggle(
        enabled: true,
        availability: BiometricAvailability.available,
        authenticate: () async => false,
      );
      expect(out, AppLockToggleOutcome.rejectedAuthFailed);
    });

    test('enabling is rejected (no prompt) when nothing is enrolled', () async {
      var prompted = false;
      final out = await evaluateAppLockToggle(
        enabled: true,
        availability: BiometricAvailability.notEnrolled,
        authenticate: () async {
          prompted = true;
          return true;
        },
      );
      expect(out, AppLockToggleOutcome.rejectedNotAvailable);
      expect(prompted, isFalse); // never prompts when unavailable
    });

    test('enabling is rejected when hardware is unavailable', () async {
      final out = await evaluateAppLockToggle(
        enabled: true,
        availability: BiometricAvailability.unavailable,
        authenticate: () async => true,
      );
      expect(out, AppLockToggleOutcome.rejectedNotAvailable);
    });
  });
}
