# Changelog

## 1.0.0

Initial stable release of `biometric_vault`: encrypted storage for small
secrets (tokens, passwords, key material) with optional biometric protection.

### Features

- Named encrypted stores with a four-call lifecycle: `canAuthenticate()`,
  `getStorage()`, then `read()` / `write()` / `delete()`.
- Android 7.0+ (API 24): AES-GCM key in the Android Keystore (StrongBox when
  available, TEE fallback), gated by `BiometricPrompt` with Class 3 biometrics
  and optional device-credential fallback. All keystore and file work runs off
  the main thread, and writes are atomic.
- iOS 13+ / macOS 10.15+: Keychain items protected by `SecAccessControl`
  (Face ID / Touch ID / Apple Watch, optional passcode fallback), shipped as a
  Swift Package Manager package with a CocoaPods fallback. Keychain operations
  run off the main thread.
- Linux (libsecret), Windows (Credential Manager), and web (`localStorage`,
  not secure) backends so cross-platform code keeps working without
  authentication support.
- Typed, sealed error model: every failure is a subtype of the sealed
  `BiometricVaultException` (`AuthException` with 14 dedicated
  `AuthExceptionCode` values, `StorageInvalidatedException` with a
  `StorageInvalidatedReason`, or `BiometricVaultPluginException`), so a
  single `switch` handles all outcomes exhaustively and raw
  `PlatformException`s never escape.
- Precise capability reporting: `canAuthenticate()` distinguishes biometry
  lockout (`errorLockedOut`) and pending security updates
  (`errorSecurityUpdateRequired`) from generic hardware unavailability.
- `StorageFileInitOptions` with explicit per-platform durations
  (`androidAuthenticationValidityDuration`,
  `darwinTouchIDAuthenticationAllowableReuseDuration`,
  `darwinTouchIDAuthenticationForceReuseContextDuration`) and per-platform
  `biometricOnly` flags. Invalid store names or option combinations throw
  `ArgumentError` at `getStorage` instead of failing natively at first use.
- Localizable prompt strings via `PromptInfo` (`AndroidPromptInfo` and
  `DarwinPromptInfo`).
