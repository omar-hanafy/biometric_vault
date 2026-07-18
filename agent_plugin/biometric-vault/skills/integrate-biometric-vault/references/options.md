# Choosing StorageFileInitOptions

## The one rule that outranks all others

**Options are fixed when a store name is first created.** Passing different
options for an existing name does not change behavior: Android key
parameters are baked into the Keystore key at generation, and Darwin access
control is baked into the keychain item. Worse, toggling `silentWrites`
changes the Android backing file (`<name>.v2.txt` vs `<name>.v3.txt`), so the
existing value simply appears as `null`. To change options: `delete()` the
store, recreate it with the new options, and re-provision the value (users
re-authenticate or sign in again). When iterating during development, either
delete first or use a fresh store name.

## Option semantics

| Option | Platform | Default | Effect |
|---|---|---|---|
| `authenticationRequired` | all | `true` | `false` = keystore/keychain encryption only, NO prompt ever; any code in the app can read. Required `false` on Linux (native init rejects `true`). |
| `androidBiometricOnly` | Android | `true` | `true` = Class 3 biometrics only, cancel button shown. `false` = system offers PIN/pattern/password fallback; needs API 30+ (silently ignored below) and REQUIRES `androidAuthenticationValidityDuration` (else `ArgumentError` at `getStorage`). |
| `androidAuthenticationValidityDuration` | Android | `null` | `null` = auth-per-use key: a fresh biometric authentication cryptographically bound (CryptoObject) to every operation. Set = time-bound key: one authentication unlocks the key for the window, device credential accepted (API 30+), and the prompt only appears when the window expired. |
| `darwinBiometricOnly` | iOS/macOS | `true` | `true` = `.biometryCurrentSet`: passcode NOT accepted, and the item becomes unreadable if the user re-enrolls biometry. `false` = `.userPresence`: passcode fallback offered, item survives re-enrollment. |
| `darwinTouchIDAuthenticationAllowableReuseDuration` | iOS/macOS | `null` | Grace period after a device unlock with Touch ID (system-capped at 5 minutes, clamped natively). Does NOT cover repeat keychain prompts. |
| `darwinTouchIDAuthenticationForceReuseContextDuration` | iOS/macOS | `null` | The plugin reuses one authenticated `LAContext` for this long, so reads/writes within the window do not re-prompt. This is the darwin equivalent of the Android validity duration. |
| `silentWrites` | Android/iOS/macOS | `false` | `write()` never prompts while `read()` stays gated. Android: envelope encryption (fresh AES-256-GCM data key wrapped by a Keystore RSA public key; only the private/read half is auth-gated). Darwin: write replaces the keychain item, which never evaluates access control. No effect when `authenticationRequired` is `false`. |

## Enrollment-change (invalidation) behavior on Android

- Auth-per-use and silent-writes read keys are invalidated when the user
  adds or removes a biometric (platform default, intentionally kept). Reads
  then throw `StorageInvalidatedException`; recovery is `delete()` ->
  re-authenticate the user by other means -> `write()` the fresh secret.
  With `silentWrites`, writes keep succeeding after invalidation, but a
  write alone does NOT heal the store (it still encrypts to the dead key
  pair) - `delete()` must come first.
- Time-bound keys (validity duration set) allow the device credential and
  are NOT invalidated by biometric enrollment changes - choose this when
  surviving enrollment changes matters more than biometric-only binding.
- Darwin mirror: `darwinBiometricOnly: true` invalidates on re-enrollment,
  `false` survives it.

## Store names

Plain identifiers only: non-empty, no `/` or `\` (and not `.`/`..`).
Anything else throws `ArgumentError` before any platform code runs. Each
name is an isolated store with its own key; prefer several small stores over
one JSON blob when values have different protection needs.

## Pairing with canAuthenticate

Call `canAuthenticate(options: sameOptions)` with the SAME options the store
will use, so the capability check matches the authenticators that will
actually gate it (e.g. `androidBiometricOnly: false` also accepts an
enrolled device credential). Treat `statusUnknown` as "attempt and handle
failure", not as an error. With `authenticationRequired: false` the check
always reports `success`.

## Recommended presets

| Use case | Options |
|---|---|
| Read-rarely secret (e.g. e2e encryption key) | defaults (auth-per-use, biometric-only) |
| Refresh token rotated by background code | `silentWrites: true` |
| Frequent reads in one flow | `androidAuthenticationValidityDuration` + `darwinTouchIDAuthenticationForceReuseContextDuration` (for example 30s) |
| Must survive enrollment changes / passcode fallback wanted | `androidBiometricOnly: false` + validity duration; `darwinBiometricOnly: false` |
| Capability fallback (no biometrics available) | `authenticationRequired: false` (understand: no gate at all) |
| App-lock screen (no stored value needed) | no store - use `BiometricVault().authenticate()` |
