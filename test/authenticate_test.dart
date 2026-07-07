import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  group('authenticate', () {
    test('sends biometricOnly and android prompt info on Android', () async {
      harness.handler = (call) => true;
      await BiometricVault().authenticate(biometricOnly: true);
      final call = harness.single;
      expect(call.method, 'authenticate');
      final args = harness.argumentsOf(call);
      expect(args['biometricOnly'], true);
      expect(args['androidPromptInfo'], isA<Map<Object?, Object?>>());
      expect(args.containsKey('iosPromptInfo'), isFalse);
    });

    test('defaults to biometricOnly false', () async {
      harness.handler = (call) => true;
      await BiometricVault().authenticate();
      expect(harness.argumentsOf(harness.single)['biometricOnly'], false);
    });

    test('sends ios prompt info on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      harness.handler = (call) => true;
      await BiometricVault().authenticate();
      final args = harness.argumentsOf(harness.single);
      expect(args['iosPromptInfo'], isA<Map<Object?, Object?>>());
      expect(args.containsKey('androidPromptInfo'), isFalse);
    });

    test(
      'sends the macOS prompt info under the shared darwin wire key',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        harness.handler = (call) => true;
        await BiometricVault().authenticate(
          promptInfo: const PromptInfo(
            macOsPromptInfo: DarwinPromptInfo(accessTitle: 'Unlock the app'),
          ),
        );
        final args = harness.argumentsOf(harness.single);
        final promptArgs = args['iosPromptInfo']! as Map<Object?, Object?>;
        expect(promptArgs['accessTitle'], 'Unlock the app');
      },
    );

    test('maps AuthError codes to AuthException', () async {
      harness.handler = (call) => throw PlatformException(
        code: 'AuthError:UserCanceled',
        message: 'canceled',
      );
      await expectLater(
        BiometricVault().authenticate(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthExceptionCode.userCanceled,
          ),
        ),
      );
    });

    test('maps lockout to AuthExceptionCode.lockedOut', () async {
      harness.handler = (call) => throw PlatformException(
        code: 'AuthError:LockedOut',
        message: 'too many attempts',
      );
      await expectLater(
        BiometricVault().authenticate(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthExceptionCode.lockedOut,
          ),
        ),
      );
    });

    test('throws Unsupported plugin exception on windows', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await expectLater(
        BiometricVault().authenticate(),
        throwsA(
          isA<BiometricVaultPluginException>().having(
            (e) => e.code,
            'code',
            'Unsupported',
          ),
        ),
      );
      expect(harness.calls, isEmpty);
    });

    test('throws Unsupported plugin exception on linux', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await expectLater(
        BiometricVault().authenticate(),
        throwsA(
          isA<BiometricVaultPluginException>().having(
            (e) => e.code,
            'code',
            'Unsupported',
          ),
        ),
      );
      expect(harness.calls, isEmpty);
    });
  });
}
