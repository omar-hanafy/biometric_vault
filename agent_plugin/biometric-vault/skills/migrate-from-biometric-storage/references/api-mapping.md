# biometric_storage (5.x) -> biometric_vault (1.x) mapping

Verified against biometric_storage 5.0.1/5.1.x and biometric_vault 1.1.x
sources. The packages are wire- and storage-independent: biometric_vault
registers its own method channel and its own native storage and CANNOT read
values written by biometric_storage.

## Types and members

| biometric_storage | biometric_vault | Notes |
|---|---|---|
| `BiometricStorage()` | `BiometricVault()` | Same singleton-factory shape |
| `BiometricStorageFile` | `BiometricVaultFile` | Same `read`/`write`/`delete` |
| `getStorage(name, options:, forceInit:, promptInfo:)` | same signature | See the store-name rule below - do NOT reuse the old name |
| `canAuthenticate({options})` | same | Response enum gained values (below) |
| `linuxCheckAppArmorError()` | same | Unchanged |
| - | `biometryType()` | NEW: Face ID / Touch ID / fingerprint labels for UI copy |
| - | `authenticate({promptInfo, biometricOnly})` | NEW: app-lock gate without any storage; replaces local_auth-style workarounds |
| `IosPromptInfo` | `DarwinPromptInfo` | Same fields (`saveTitle`, `accessTitle`) |
| `AndroidPromptInfo`, `PromptInfo` | same names | Unchanged fields; `PromptInfo(iosPromptInfo:, macOsPromptInfo:)` now take `DarwinPromptInfo` |
| `BiometricStorageException` | `BiometricVaultPluginException` | New type adds `code` and `details` |
| `AuthException` | `AuthException` | Same name, richer `code` enum, now part of a sealed hierarchy |
| - | `StorageInvalidatedException` | NEW: permanent data loss (key invalidated / corrupted); previously leaked as raw `PlatformException` or `unknown` |
| - | sealed `BiometricVaultException` base | Enables one exhaustive `switch` |

## StorageFileInitOptions

Field names are identical in 5.1.x and 1.x
(`androidAuthenticationValidityDuration`,
`darwinTouchIDAuthenticationAllowableReuseDuration`,
`darwinTouchIDAuthenticationForceReuseContextDuration`,
`authenticationRequired`, `androidBiometricOnly`, `darwinBiometricOnly`).
biometric_vault adds `silentWrites` and its constructor is `const`.

**5.0.x deprecated parameter** `authenticationValidityDurationSeconds: N`
set BOTH `androidAuthenticationValidityDuration` AND
`darwinTouchIDAuthenticationAllowableReuseDuration` to N seconds. Migration
requires a judgment call on darwin:

- Faithful mapping: `androidAuthenticationValidityDuration: Duration(seconds: N)`
  plus `darwinTouchIDAuthenticationAllowableReuseDuration: Duration(seconds: N)`
  (grace period only after device unlock via Touch ID; system caps at 5 min).
- Intended behavior for most apps ("one prompt per window"):
  `androidAuthenticationValidityDuration` plus
  `darwinTouchIDAuthenticationForceReuseContextDuration` - the reused
  authenticated context actually suppresses repeat keychain prompts.

Ask which behavior the app wants; default to the second with a note.

## Error handling changes (compile-fine, behave-differently risk)

Old `AuthExceptionCode` had only `{userCanceled, canceled, unknown, timeout,
linuxAppArmorDenied}`; every other failure (lockout, no enrollment, no
hardware...) arrived as `unknown` or a raw `PlatformException`. New code has
14 specific values. Consequences:

- `if (e.code == AuthExceptionCode.unknown)` branches that handled lockout
  or enrollment loss must be rewritten against the specific codes
  (`lockedOut`, `lockedOutPermanently`, `noBiometricEnrolled`, ...).
- Android Keystore invalidation (user re-enrolled biometrics) now throws
  `StorageInvalidatedException` instead of an opaque error. Handle it with
  delete -> re-auth -> rewrite, or users hit unrecoverable reads.
- `CanAuthenticateResponse` gained `errorLockedOut` and
  `errorSecurityUpdateRequired`; exhaustive switches need the new cases.
- Old catch of `BiometricStorageException` -> catch
  `BiometricVaultPluginException` (or better, switch over the sealed
  `BiometricVaultException`).

## Native storage independence (why data must be migrated in-app)

| Platform | biometric_storage | biometric_vault | Collision? |
|---|---|---|---|
| Android files | `<filesDir>/biometric_storage/<name>.v2.txt` | `<filesDir>/biometric_vault/<name>.v2.txt`/`.v3.txt` | none |
| Android Keystore alias | `_CM_<name>_master_key` | `_CM_<name>_master_key` (+ `_EM_...` for silent writes) | **YES - identical alias for identical store name** |
| iOS/macOS keychain service | `flutter_biometric_storage` | `flutter_biometric_vault` | none |
| Linux/Windows/web prefix | `design.codeux.authpass.` | `io.github.omarhanafy.authpass.` | none |
| Method channel | `biometric_storage` | `biometric_vault` | none |

**The store-name rule:** while both packages are installed, a
biometric_vault store with the SAME name as a biometric_storage store shares
its Android Keystore alias. The vault would encrypt with the key the old
plugin created, and deleting the old store afterwards deletes that shared
key - destroying the freshly migrated value. Always migrate to a NEW name
(for example `refresh_token` -> `refresh_token_v2`). With distinct names,
the two packages are fully independent on every platform and can safely
coexist during the migration window.

## Gradle/CocoaPods coexistence

Different Android namespaces (`design.codeux.biometric_storage` vs
`io.github.omarhanafy.biometric_vault`) and different pod/SPM module names;
both packages build side by side in one app with no configuration.
