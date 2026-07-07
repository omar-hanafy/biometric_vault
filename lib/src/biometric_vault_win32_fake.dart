/// Non-`dart:io` stand-in for the Windows implementation.
///
/// The conditional export in `package:biometric_vault/biometric_vault.dart`
/// selects this empty declaration on platforms without `dart:io` (the web),
/// where the real win32-backed class can never run.
class Win32BiometricVaultPlugin {}
