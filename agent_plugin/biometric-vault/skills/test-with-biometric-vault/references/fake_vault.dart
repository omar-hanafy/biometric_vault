// A ready-to-adapt in-memory fake for biometric_vault, for consumer tests.
//
// Copy this file into your app's test/ directory (e.g. test/fake_vault.dart).
// It uses only the package's public, supported extension surface: the
// `BiometricVault.create()` constructor and the `BiometricVault.instance`
// setter, so it never touches the plugin's internal method-channel protocol
// and keeps working across plugin releases.
//
// Usage in a test:
//
//   final vault = FakeBiometricVault();
//   BiometricVault.instance = vault;              // app code's
//   vault.values['refresh_token'] = 'stored';     // BiometricVault() now
//   vault.nextReadError =                         // returns the fake
//       const AuthException(AuthExceptionCode.userCanceled, 'canceled');
//
// Restore the real implementation when a test suite needs it again:
//   BiometricVault.instance = MethodChannelBiometricVault();
import 'package:biometric_vault/biometric_vault.dart';

/// In-memory [BiometricVault] with scriptable failures.
class FakeBiometricVault extends BiometricVault {
  FakeBiometricVault() : super.create();

  /// Stored values by store name. Seed or inspect directly.
  final Map<String, String> values = {};

  /// Options captured from [getStorage], by store name.
  final Map<String, StorageFileInitOptions> capturedOptions = {};

  /// What [canAuthenticate] reports.
  CanAuthenticateResponse canAuthenticateResponse =
      CanAuthenticateResponse.success;

  /// What [biometryType] reports.
  BiometryType biometryTypeResponse = BiometryType.faceId;

  /// Thrown by the next [BiometricVaultFile.read] / `write` / `delete` /
  /// [authenticate] call, then cleared. Use the real exception types, e.g.
  /// `AuthException(AuthExceptionCode.lockedOut, 'locked')` or
  /// `StorageInvalidatedException(StorageInvalidatedReason.keyInvalidated,
  /// 'enrollment changed')`.
  BiometricVaultException? nextReadError;
  BiometricVaultException? nextWriteError;
  BiometricVaultException? nextDeleteError;
  BiometricVaultException? nextAuthenticateError;

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async => canAuthenticateResponse;

  @override
  Future<BiometryType> biometryType() async => biometryTypeResponse;

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<void> authenticate({
    PromptInfo promptInfo = PromptInfo.defaultValues,
    bool biometricOnly = false,
  }) async {
    _throwIfSet(nextAuthenticateError, () => nextAuthenticateError = null);
  }

  @override
  Future<BiometricVaultFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    // Mirror the real fail-fast name validation so tests catch bad names.
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
      throw ArgumentError.value(name, 'name', 'Invalid storage name.');
    }
    capturedOptions[name] = options ?? const StorageFileInitOptions();
    return BiometricVaultFile(this, name, promptInfo);
  }

  @override
  Future<String?> read(String name, PromptInfo promptInfo) async {
    _throwIfSet(nextReadError, () => nextReadError = null);
    return values[name];
  }

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) async {
    _throwIfSet(nextWriteError, () => nextWriteError = null);
    values[name] = content;
  }

  @override
  Future<bool?> delete(String name, PromptInfo promptInfo) async {
    _throwIfSet(nextDeleteError, () => nextDeleteError = null);
    return values.remove(name) != null;
  }

  void _throwIfSet(BiometricVaultException? error, void Function() clear) {
    if (error != null) {
      clear();
      throw error;
    }
  }
}
