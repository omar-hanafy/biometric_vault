@TestOn('vm')
library;

import 'package:biometric_vault/biometric_vault.dart'
    hide Win32BiometricVaultPlugin;
import 'package:biometric_vault/src/biometric_vault_win32.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vault = Win32BiometricVaultPlugin();

  group('Windows storage initialization', () {
    for (final name in ['', '.', '..', 'a/b', r'a\b', 'a\u0000b']) {
      test('rejects invalid name "$name" before credential access', () async {
        await expectLater(vault.getStorage(name), throwsArgumentError);
      });
    }

    test('preserves the existing credential namespace', () async {
      final file = await vault.getStorage('my_store.v2');
      expect(file.name, '${Win32BiometricVaultPlugin.namePrefix}my_store.v2');
    });

    test('reports unauthenticated fallback capability', () async {
      expect(
        await vault.canAuthenticate(),
        CanAuthenticateResponse.errorHwUnavailable,
      );
      expect(await vault.biometryType(), BiometryType.none);
      await expectLater(
        vault.authenticate(),
        throwsA(
          isA<BiometricVaultPluginException>().having(
            (error) => error.code,
            'code',
            'Unsupported',
          ),
        ),
      );
    });
  });
}
