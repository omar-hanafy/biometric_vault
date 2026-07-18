# Changelog

## 1.1.1

No runtime changes.

- AI coding-assistant support: the repository now ships an installable agent
  plugin for Claude Code and OpenAI Codex with four package-specific skills:
  `integrate-biometric-vault` (integration with per-platform setup),
  `troubleshoot-biometric-vault` (symptom-to-fix diagnosis),
  `test-with-biometric-vault` (faking the vault in consumer tests), and
  `migrate-from-biometric-storage` (safe API and data migration). See the
  "AI coding-assistant support" section of the README for installation.
- Repository-level agent guidance (`AGENTS.md`) and a plugin validation
  script (`tool/validate_agent_plugin.dart`) wired into CI. The plugin tree
  is distributed from the Git repository and excluded from the pub.dev
  archive.

## 1.1.0

- `StorageFileInitOptions.silentWrites`: writes never show an authentication
  prompt while reads stay gated. Android uses envelope encryption (payload
  under a fresh AES-256-GCM key, wrapped by a Keystore RSA public key whose
  private half is authentication-gated); iOS and macOS replace the keychain
  item on write, which never evaluates its access control.
- `BiometricVault.biometryType()`: reports the device biometry modality
  (Face ID, Touch ID, Optic ID, fingerprint, face, iris) so UI copy can name
  the actual authenticator.
- `BiometricVault.authenticate()`: standalone user authentication without any
  storage, for app-lock style privacy gates. Supports biometric-only mode or
  device-credential fallback.

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
