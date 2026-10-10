@TestOn('browser')
library;

import 'package:biometric_vault/biometric_vault.dart';
import 'package:biometric_vault/src/biometric_vault_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vault = BiometricVaultPluginWeb();
  late BiometricVaultFile file;

  setUp(() async {
    file = await vault.getStorage('browser_regression_test');
    await file.delete();
  });

  tearDown(() => file.delete());

  test(
    'localStorage round-trips Unicode, empty content and deletion',
    () async {
      expect(await file.read(), isNull);
      await file.write('secret العربية 🔐');
      expect(await file.read(), 'secret العربية 🔐');
      await file.write('');
      expect(await file.read(), '');
      await file.delete();
      expect(await file.read(), isNull);
      await file.delete();
    },
  );

  test('quota failure is typed and preserves the previous value', () async {
    await file.write('previous secret');
    await expectLater(
      file.write('x' * (10 * 1024 * 1024)),
      throwsA(
        isA<BiometricVaultPluginException>().having(
          (error) => error.code,
          'code',
          'WriteError',
        ),
      ),
    );
    expect(await file.read(), 'previous secret');
  });

  test('storage names keep the existing localStorage namespace', () {
    expect(
      file.name,
      '${BiometricVaultPluginWeb.namePrefix}browser_regression_test',
    );
  });

  for (final name in ['', '.', '..', 'a/b', r'a\b', 'a\u0000b']) {
    test('rejects invalid name "$name" before localStorage access', () async {
      await expectLater(vault.getStorage(name), throwsArgumentError);
    });
  }

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
}
