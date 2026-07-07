import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'channel_harness.dart';

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

  group('biometryType wire mapping', () {
    for (final entry in const {
      'None': BiometryType.none,
      'FaceId': BiometryType.faceId,
      'TouchId': BiometryType.touchId,
      'OpticId': BiometryType.opticId,
      'Fingerprint': BiometryType.fingerprint,
      'Face': BiometryType.face,
      'Iris': BiometryType.iris,
      'Multiple': BiometryType.multiple,
      'Unknown': BiometryType.unknown,
    }.entries) {
      test('maps ${entry.key}', () async {
        harness.handler = (call) => entry.key;
        expect(await BiometricVault().biometryType(), entry.value);
        expect(harness.single.method, 'biometryType');
      });
    }

    test(
      'unrecognized wire value maps to unknown (forward compatible)',
      () async {
        harness.handler = (call) => 'SomethingNew';
        expect(await BiometricVault().biometryType(), BiometryType.unknown);
      },
    );

    test('iOS and macOS also go through the channel', () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        harness.calls.clear();
        debugDefaultTargetPlatformOverride = platform;
        harness.handler = (call) => 'FaceId';
        expect(await BiometricVault().biometryType(), BiometryType.faceId);
        expect(harness.single.method, 'biometryType');
      }
    });

    test('returns none on windows without touching the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(await BiometricVault().biometryType(), BiometryType.none);
      expect(harness.calls, isEmpty);
    });

    test('returns none on linux without touching the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await BiometricVault().biometryType(), BiometryType.none);
      expect(harness.calls, isEmpty);
    });
  });
}
