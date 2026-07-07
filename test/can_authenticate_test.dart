import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'channel_harness.dart';

/// Every wire string the native `canAuthenticate` implementations may return,
/// paired with the public enum value it must map to. This is the frozen v6
/// contract; the same table exists in the Kotlin and Swift sources.
const wireToResponse = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorPasscodeNotSet': CanAuthenticateResponse.errorPasscodeNotSet,
  'ErrorLockedOut': CanAuthenticateResponse.errorLockedOut,
  'ErrorSecurityUpdateRequired':
      CanAuthenticateResponse.errorSecurityUpdateRequired,
  'ErrorStatusUnknown': CanAuthenticateResponse.statusUnknown,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
};

void main() {
  final harness = ChannelHarness();

  setUp(() {
    harness.calls.clear();
    harness.handler = null;
    harness.install();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    harness.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  group('wire mapping', () {
    for (final MapEntry(key: wire, value: response) in wireToResponse.entries) {
      test('$wire maps to $response', () async {
        harness.handler = (call) => wire;
        expect(await BiometricVault().canAuthenticate(), response);
      });
    }

    test('an unknown wire string fails loud with StateError', () async {
      harness.handler = (call) => 'ErrorFromTheFuture';
      expect(() => BiometricVault().canAuthenticate(), throwsStateError);
    });
  });

  group('request payload', () {
    test('sends default options when none are given', () async {
      harness.handler = (call) => 'Success';
      await BiometricVault().canAuthenticate();
      final call = harness.single;
      expect(call.method, 'canAuthenticate');
      expect(
        harness.argumentsOf(call)['options'],
        StorageFileInitOptions().toJson(),
      );
    });

    test('sends the provided options', () async {
      harness.handler = (call) => 'Success';
      final options = StorageFileInitOptions(
        authenticationRequired: false,
        androidBiometricOnly: false,
        androidAuthenticationValidityDuration: const Duration(seconds: 12),
      );
      await BiometricVault().canAuthenticate(options: options);
      expect(harness.argumentsOf(harness.single)['options'], options.toJson());
    });
  });

  group('platform gating', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('$platform asks the native side', () async {
        debugDefaultTargetPlatformOverride = platform;
        harness.handler = (call) => 'Success';
        expect(
          await BiometricVault().canAuthenticate(),
          CanAuthenticateResponse.success,
        );
        expect(harness.calls, hasLength(1));
      });
    }

    for (final platform in [TargetPlatform.windows, TargetPlatform.fuchsia]) {
      test(
        '$platform reports unsupported without touching the channel',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          expect(
            await BiometricVault().canAuthenticate(),
            CanAuthenticateResponse.unsupported,
          );
          expect(harness.calls, isEmpty);
        },
      );
    }
  });
}
