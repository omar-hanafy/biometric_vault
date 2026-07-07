/// Encrypted storage with optional biometric protection.
///
/// Start with [BiometricVault.canAuthenticate] to check device support,
/// then open a store with [BiometricVault.getStorage] and use
/// [BiometricVaultFile.read], [BiometricVaultFile.write], and
/// [BiometricVaultFile.delete]. Every failure surfaces as a subtype of
/// the sealed [BiometricVaultException].
library;

export 'src/biometric_vault.dart';
export 'src/biometric_vault_win32_fake.dart'
    if (dart.library.io) 'src/biometric_vault_win32.dart';
