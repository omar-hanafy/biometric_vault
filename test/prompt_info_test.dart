import 'package:biometric_vault/biometric_vault.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'channel_harness.dart';

void main() {
  final harness = ChannelHarness();

  const promptInfo = PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Android title',
      subtitle: 'sub',
      description: 'desc',
      negativeButton: 'Nope',
      confirmationRequired: false,
    ),
    iosPromptInfo: DarwinPromptInfo(
      saveTitle: 'iOS save',
      accessTitle: 'iOS access',
    ),
    macOsPromptInfo: DarwinPromptInfo(
      saveTitle: 'macOS save',
      accessTitle: 'macOS access',
    ),
  );

  setUp(() {
    harness.calls.clear();
    harness.install();
  });

  tearDown(() {
    harness.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> readWith(TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    harness.handler = (call) => call.method == 'init' ? true : null;
    final file = await BiometricVault().getStorage(
      'store',
      promptInfo: promptInfo,
    );
    harness.calls.clear();
    await file.read();
  }

  group('per-platform prompt payload', () {
    test('android sends only androidPromptInfo with the exact keys', () async {
      await readWith(TargetPlatform.android);
      final args = harness.argumentsOf(harness.single);
      expect(args['androidPromptInfo'], {
        'title': 'Android title',
        'subtitle': 'sub',
        'description': 'desc',
        'negativeButton': 'Nope',
        'confirmationRequired': false,
      });
      expect(args.containsKey('iosPromptInfo'), isFalse);
    });

    test('iOS sends the ios config under the iosPromptInfo key', () async {
      await readWith(TargetPlatform.iOS);
      final args = harness.argumentsOf(harness.single);
      expect(args['iosPromptInfo'], {
        'saveTitle': 'iOS save',
        'accessTitle': 'iOS access',
      });
      expect(args.containsKey('androidPromptInfo'), isFalse);
    });

    test('macOS sends the macOs config under the shared iosPromptInfo key '
        '(same native implementation)', () async {
      await readWith(TargetPlatform.macOS);
      final args = harness.argumentsOf(harness.single);
      expect(args['iosPromptInfo'], {
        'saveTitle': 'macOS save',
        'accessTitle': 'macOS access',
      });
    });

    test('linux sends no prompt payload', () async {
      await readWith(TargetPlatform.linux);
      final args = harness.argumentsOf(harness.single);
      expect(args.keys, ['name']);
    });
  });

  group('DarwinPromptInfo', () {
    test('provides the documented defaults', () {
      const info = DarwinPromptInfo();
      expect(info.saveTitle, 'Unlock to save data');
      expect(info.accessTitle, 'Unlock to access data');
    });
  });
}
