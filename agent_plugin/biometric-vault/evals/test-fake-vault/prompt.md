Here is the service class our Flutter app uses on top of the
biometric_vault package (lib/token_store.dart):

```dart
import 'package:biometric_vault/biometric_vault.dart';

class TokenStore {
  BiometricVaultFile? _file;

  Future<BiometricVaultFile> _storage() async {
    return _file ??= await BiometricVault().getStorage(
      'refresh_token',
      options: const StorageFileInitOptions(silentWrites: true),
    );
  }

  Future<String?> readToken() async {
    try {
      return await (await _storage()).read();
    } on AuthException catch (e) {
      if (e.code == AuthExceptionCode.userCanceled) return null;
      rethrow;
    } on StorageInvalidatedException {
      await (await _storage()).delete();
      return null;
    }
  }

  Future<void> writeToken(String token) async {
    await (await _storage()).write(token);
  }
}
```

Write test/token_store_test.dart with unit tests that run with plain
`flutter test` (no device or emulator): happy-path read, user-canceled read
returning null, the invalidation path (must delete the store and return
null), and writeToken. Explain how your approach makes the plugin testable.
