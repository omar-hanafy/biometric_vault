import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'channel_harness.dart';

/// Every `AuthError:` wire code the native implementations may raise, paired
/// with the public [AuthExceptionCode] it must map to. Frozen v6 contract;
/// mirrored by the Kotlin `AuthenticationError` enum and the Swift error
/// mapping.
const wireToAuthCode = {
  'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
  'AuthError:Canceled': AuthExceptionCode.canceled,
  'AuthError:Timeout': AuthExceptionCode.timeout,
  'AuthError:LockedOut': AuthExceptionCode.lockedOut,
  'AuthError:LockedOutPermanently': AuthExceptionCode.lockedOutPermanently,
  'AuthError:AuthenticationFailed': AuthExceptionCode.authenticationFailed,
  'AuthError:NoBiometricEnrolled': AuthExceptionCode.noBiometricEnrolled,
  'AuthError:NoHardware': AuthExceptionCode.noHardware,
  'AuthError:HardwareUnavailable': AuthExceptionCode.hardwareUnavailable,
  'AuthError:PasscodeNotSet': AuthExceptionCode.passcodeNotSet,
  'AuthError:SecurityUpdateRequired': AuthExceptionCode.securityUpdateRequired,
  'AuthError:FailedToStart': AuthExceptionCode.failedToStart,
  'AuthError:Unknown': AuthExceptionCode.unknown,
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

  Future<BiometricVaultFile> storage() async {
    harness.handler = (call) => true;
    final file = await BiometricVault().getStorage('store');
    harness.calls.clear();
    return file;
  }

  group('AuthError codes', () {
    for (final MapEntry(key: wire, value: code) in wireToAuthCode.entries) {
      test('$wire maps to $code', () async {
        final file = await storage();
        harness.handler = (call) =>
            throw PlatformException(code: wire, message: 'nope');
        await expectLater(
          file.read(),
          throwsA(
            isA<AuthException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'message', 'nope'),
          ),
        );
      });
    }

    test(
      'an unknown AuthError code degrades to AuthExceptionCode.unknown',
      () async {
        final file = await storage();
        harness.handler = (call) =>
            throw PlatformException(code: 'AuthError:FromTheFuture');
        await expectLater(
          file.read(),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              AuthExceptionCode.unknown,
            ),
          ),
        );
      },
    );
  });

  group('StorageError codes', () {
    test('KeyInvalidated maps to StorageInvalidatedException', () async {
      final file = await storage();
      harness.handler = (call) => throw PlatformException(
        code: 'StorageError:KeyInvalidated',
        message: 'The Android Keystore entry was invalidated.',
      );
      await expectLater(
        file.read(),
        throwsA(
          isA<StorageInvalidatedException>()
              .having(
                (e) => e.reason,
                'reason',
                StorageInvalidatedReason.keyInvalidated,
              )
              .having((e) => e.message, 'message', contains('invalidated')),
        ),
      );
    });

    test('CorruptedData maps to StorageInvalidatedException', () async {
      final file = await storage();
      harness.handler = (call) => throw PlatformException(
        code: 'StorageError:CorruptedData',
        message: 'bad payload',
      );
      await expectLater(
        file.write('value'),
        throwsA(
          isA<StorageInvalidatedException>().having(
            (e) => e.reason,
            'reason',
            StorageInvalidatedReason.corruptedData,
          ),
        ),
      );
    });
  });

  group('other platform errors', () {
    test('are wrapped preserving code, message and details', () async {
      final file = await storage();
      harness.handler = (call) => throw PlatformException(
        code: 'SecurityError',
        message: 'Error while writing data: -25293',
        details: 'stack',
      );
      await expectLater(
        file.write('value'),
        throwsA(
          isA<BiometricVaultPluginException>()
              .having((e) => e.code, 'code', 'SecurityError')
              .having((e) => e.message, 'message', contains('-25293'))
              .having((e) => e.details, 'details', 'stack'),
        ),
      );
    });

    test('getStorage init errors surface typed too', () async {
      harness.handler = (call) => throw PlatformException(
        code: 'AlreadyInitialized',
        message: 'already there',
      );
      await expectLater(
        BiometricVault().getStorage('store2', forceInit: true),
        throwsA(
          isA<BiometricVaultPluginException>().having(
            (e) => e.code,
            'code',
            'AlreadyInitialized',
          ),
        ),
      );
    });

    test('delete errors surface typed', () async {
      final file = await storage();
      harness.handler = (call) =>
          throw PlatformException(code: 'NoSuchStorage', message: 'gone');
      await expectLater(
        file.delete(),
        throwsA(isA<BiometricVaultPluginException>()),
      );
    });
  });

  group('Linux AppArmor detection', () {
    test('detects the denial from the error details message', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final file = await storage();
      harness.handler = (call) => throw PlatformException(
        code: 'Unknown',
        message: 'read failure',
        details: {
          'message':
              'org.freedesktop.DBus.Error.AccessDenied: An AppArmor policy'
              ' prevents this sender from sending this message',
        },
      );
      await expectLater(
        file.read(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AuthExceptionCode.linuxAppArmorDenied,
          ),
        ),
      );
    });
  });

  group('exception hierarchy', () {
    test('all plugin exceptions share the sealed base type', () async {
      // The switch below only compiles while BiometricVaultException stays
      // sealed with exactly these three subtypes; it doubles as a regression
      // guard for the public hierarchy.
      String describe(BiometricVaultException e) => switch (e) {
        AuthException(:final code) => 'auth:$code',
        StorageInvalidatedException(:final reason) => 'storage:$reason',
        BiometricVaultPluginException(:final code) => 'plugin:$code',
      };

      expect(
        describe(const AuthException(AuthExceptionCode.lockedOut, 'm')),
        'auth:AuthExceptionCode.lockedOut',
      );
      expect(
        describe(
          const StorageInvalidatedException(
            StorageInvalidatedReason.keyInvalidated,
            'm',
          ),
        ),
        'storage:StorageInvalidatedReason.keyInvalidated',
      );
      expect(
        describe(const BiometricVaultPluginException('X', 'm', null)),
        'plugin:X',
      );
    });

    test('a catch-all on the base type catches every subtype', () async {
      final file = await storage();
      harness.handler = (call) =>
          throw PlatformException(code: 'RetrieveError', message: 'oops');
      Object? caught;
      try {
        await file.read();
      } on BiometricVaultException catch (e) {
        caught = e;
      }
      expect(caught, isA<BiometricVaultPluginException>());
    });

    test('non-platform errors propagate untouched', () async {
      final file = await storage();
      harness.uninstall();
      await expectLater(file.read(), throwsA(isA<MissingPluginException>()));
      harness.install();
    });
  });
}
