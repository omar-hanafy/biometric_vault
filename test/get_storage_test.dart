import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'channel_harness.dart';

void main() {
  final harness = ChannelHarness();

  setUp(() {
    harness.calls.clear();
    harness.handler = (call) => call.method == 'init' ? true : null;
    harness.install();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    harness.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  group('getStorage', () {
    test('sends name, options and forceInit to init', () async {
      final options = StorageFileInitOptions(authenticationRequired: false);
      await BiometricVault().getStorage(
        'mystore',
        options: options,
        forceInit: true,
      );
      final call = harness.single;
      expect(call.method, 'init');
      expect(harness.argumentsOf(call), {
        'name': 'mystore',
        'options': options.toJson(),
        'forceInit': true,
      });
    });

    test('defaults options and forceInit', () async {
      await BiometricVault().getStorage('mystore');
      final args = harness.argumentsOf(harness.single);
      expect(args['options'], StorageFileInitOptions().toJson());
      expect(args['forceInit'], false);
    });

    group('name validation', () {
      for (final bad in ['', 'a/b', r'a\b', '../escape']) {
        test("rejects '$bad' before any platform call", () async {
          await expectLater(
            BiometricVault().getStorage(bad),
            throwsArgumentError,
          );
          expect(harness.calls, isEmpty);
        });
      }

      test('accepts plain names with dots and underscores', () async {
        await BiometricVault().getStorage('my_store.v2');
        expect(harness.calls, hasLength(1));
      });
    });

    group('android options validation', () {
      test('rejects androidBiometricOnly=false without a validity duration '
          'on android', () async {
        await expectLater(
          BiometricVault().getStorage(
            'store',
            options: StorageFileInitOptions(androidBiometricOnly: false),
          ),
          throwsArgumentError,
        );
        expect(harness.calls, isEmpty);
      });

      test(
        'accepts androidBiometricOnly=false with a validity duration',
        () async {
          await BiometricVault().getStorage(
            'store',
            options: StorageFileInitOptions(
              androidBiometricOnly: false,
              androidAuthenticationValidityDuration: const Duration(
                seconds: 10,
              ),
            ),
          );
          expect(harness.calls, hasLength(1));
        },
      );

      test('does not apply the android rule on iOS', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await BiometricVault().getStorage(
          'store',
          options: StorageFileInitOptions(androidBiometricOnly: false),
        );
        expect(harness.calls, hasLength(1));
      });
    });
  });

  group('BiometricVaultFile operations', () {
    Future<BiometricVaultFile> storage() async {
      final file = await BiometricVault().getStorage('store');
      harness.calls.clear();
      return file;
    }

    test('read sends the name and returns the stored value', () async {
      final file = await storage();
      harness.handler = (call) => 'secret';
      expect(await file.read(), 'secret');
      final call = harness.single;
      expect(call.method, 'read');
      expect(harness.argumentsOf(call)['name'], 'store');
    });

    test('read returns null when nothing is stored', () async {
      final file = await storage();
      harness.handler = (call) => null;
      expect(await file.read(), isNull);
    });

    test('write sends name and content', () async {
      final file = await storage();
      harness.handler = (call) => null;
      await file.write('payload');
      final call = harness.single;
      expect(call.method, 'write');
      final args = harness.argumentsOf(call);
      expect(args['name'], 'store');
      expect(args['content'], 'payload');
    });

    test('delete sends the name', () async {
      final file = await storage();
      harness.handler = (call) => true;
      await file.delete();
      final call = harness.single;
      expect(call.method, 'delete');
      expect(harness.argumentsOf(call)['name'], 'store');
    });

    test('a per-call promptInfo overrides the storage default', () async {
      final file = await BiometricVault().getStorage(
        'store',
        promptInfo: const PromptInfo(
          androidPromptInfo: AndroidPromptInfo(title: 'Default title'),
        ),
      );
      harness.calls.clear();
      harness.handler = (call) => 'x';

      await file.read();
      await file.read(
        promptInfo: const PromptInfo(
          androidPromptInfo: AndroidPromptInfo(title: 'Custom title'),
        ),
      );

      String titleOf(int index) {
        final args = harness.argumentsOf(harness.calls[index]);
        final prompt = args['androidPromptInfo'] as Map<Object?, Object?>;
        return prompt['title'] as String;
      }

      expect(titleOf(0), 'Default title');
      expect(titleOf(1), 'Custom title');
    });
  });
}
