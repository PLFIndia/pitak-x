import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/screen_security.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

void main() {
  group('shouldSecureForState (#34/F-12)', () {
    test('secures only when the vault is unlocked', () {
      expect(shouldSecureForState(const VaultUninitialized()), isFalse);
      expect(shouldSecureForState(const VaultLocked()), isFalse);
      expect(
        shouldSecureForState(const VaultUnlocked(VaultData.empty)),
        isTrue,
      );
    });
  });
}
