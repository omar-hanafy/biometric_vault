import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageFileInitOptions.toJson', () {
    test('defaults serialize with the exact v5-compatible wire keys', () {
      expect(StorageFileInitOptions().toJson(), {
        'androidAuthenticationValidityDurationSeconds': null,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': null,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': null,
        'authenticationRequired': true,
        'androidBiometricOnly': true,
        'darwinBiometricOnly': true,
      });
    });

    test('durations serialize as whole seconds', () {
      final options = StorageFileInitOptions(
        androidAuthenticationValidityDuration: const Duration(seconds: 30),
        darwinTouchIDAuthenticationAllowableReuseDuration: const Duration(
          minutes: 1,
        ),
        darwinTouchIDAuthenticationForceReuseContextDuration: const Duration(
          seconds: 45,
        ),
        authenticationRequired: false,
        androidBiometricOnly: false,
        darwinBiometricOnly: false,
      );
      expect(options.toJson(), {
        'androidAuthenticationValidityDurationSeconds': 30,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 60,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': 45,
        'authenticationRequired': false,
        'androidBiometricOnly': false,
        'darwinBiometricOnly': false,
      });
    });

    test('allowable-reuse no longer implies force-reuse '
        '(the two darwin durations are independent)', () {
      final options = StorageFileInitOptions(
        darwinTouchIDAuthenticationAllowableReuseDuration: const Duration(
          seconds: 10,
        ),
      );
      expect(
        options.darwinTouchIDAuthenticationForceReuseContextDuration,
        isNull,
      );
      expect(
        options
            .toJson()['darwinTouchIDAuthenticationForceReuseContextDurationSeconds'],
        isNull,
      );
    });

    test('force-reuse can be set without allowable-reuse', () {
      final options = StorageFileInitOptions(
        darwinTouchIDAuthenticationForceReuseContextDuration: const Duration(
          seconds: 20,
        ),
      );
      expect(options.darwinTouchIDAuthenticationAllowableReuseDuration, isNull);
      expect(
        options
            .toJson()['darwinTouchIDAuthenticationForceReuseContextDurationSeconds'],
        20,
      );
    });
  });
}
