# biometric_vault failure reference (symptom -> cause -> fix)

Every failure surfaces as one of three sealed subtypes of
`BiometricVaultException`:

- `AuthException(code)` - the user could not or did not authenticate. Data
  is untouched; the operation can be retried.
- `StorageInvalidatedException(reason)` - the stored value is permanently
  unrecoverable. NOT retryable.
- `BiometricVaultPluginException(code, message, details)` - unexpected
  platform failure; usually an integration bug worth fixing, not catching.

## AuthExceptionCode

| Code | Platforms | Meaning | Reaction |
|---|---|---|---|
| `userCanceled` | all | User dismissed the prompt (negative button, back, canceled sheet; also the darwin fallback button when no fallback exists) | No error UI; user knows |
| `canceled` | all | System canceled: app backgrounded, focus lost, UI could not show | Retry when app active |
| `timeout` | Android | Prompt timed out waiting | Offer retry |
| `lockedOut` | all | Too many failed attempts; temporary. Android: clears after ~30s. iOS/macOS: clears after a successful device-passcode authentication | Tell the user; retry later, or use a store with credential fallback |
| `lockedOutPermanently` | Android | Locked until the user unlocks the device with PIN/pattern/password | Direct user to lock/unlock device |
| `authenticationFailed` | all | User not recognized (darwin: keychain `errSecAuthFailed` after ruling out lockout; Android: sensor could not process) | Offer retry |
| `noBiometricEnrolled` | Android | Enrollment removed between check and prompt | Re-run `canAuthenticate`, guide to enroll |
| `noHardware` / `hardwareUnavailable` | Android | No sensor / sensor busy | Fall back per product |
| `passcodeNotSet` | Android | Credential fallback requested but no PIN/pattern/password exists | Guide to set a credential |
| `securityUpdateRequired` | Android | Sensor disabled until a security update | Inform user |
| `failedToStart` | Android | See dedicated section below | Fix integration |
| `linuxAppArmorDenied` | Linux | Snap AppArmor denies the Secret Service | `snap connect <app>:password-manager-service` |
| `unknown` | all | Unmapped platform error; message carries details | Log and report |

### failedToStart (Android) - always an integration bug

Emitted in exactly one condition: the plugin has no `FragmentActivity` when
a prompt must be shown. Causes, in order of likelihood:

1. `MainActivity` extends `FlutterActivity` instead of
   `FlutterFragmentActivity` (the plugin logs
   `"Attached activity ... is not a FragmentActivity"` and discards it).
   Check the SHIPPED variant's manifest and activity, not just the repo -
   debug/flavor manifests can point at a different activity.
2. The call runs while no activity is attached: background isolate (FCM
   background handler, WorkManager, headless engine) or fully backgrounded
   app. Storage calls that prompt must run in the foreground UI isolate.

Note the masking interplay: with `silentWrites` stores, writes never need
the activity, so a `FlutterActivity` regression stays invisible until the
first gated read. Also confirm the activity theme inherits from
`Theme.AppCompat` (both `values/` and `values-night/`), or the prompt
crashes instead.

## StorageInvalidatedException

| Reason | Cause |
|---|---|
| `keyInvalidated` | Android Keystore invalidated the key - the user added or removed a biometric (platform default for auth-per-use keys, deliberately kept). Note the darwin difference: an item stored with `darwinBiometricOnly: true` (`.biometryCurrentSet`) becomes unreadable after re-enrollment too, but surfaces as repeated `AuthException(authenticationFailed)` on reads, NOT as `StorageInvalidatedException` - recovery (delete + re-provision) is the same. |
| `corruptedData` | Payload exists but fails parsing/authentication (truncated file, GCM tag mismatch) |

Recovery is always the same three steps, in this order:

```dart
await store.delete();     // removes the dead key AND the payload; never prompts
// re-authenticate the user by other means (sign-in)
await store.write(fresh); // generates a fresh key bound to current biometrics
```

Silent-writes trap: after invalidation, `write()` still SUCCEEDS (the RSA
public half survives) but does NOT heal the store - new values are wrapped
for the dead private key and reads keep failing. `delete()` first is
mandatory. Conversely "writes work, reads fail" on a silent-writes store is
the expected invalidation signature, not corruption.

Keys that survive enrollment changes: Android time-bound keys
(`androidAuthenticationValidityDuration` set, which also allows the device
credential) and darwin `.userPresence` items (`darwinBiometricOnly: false`).
Switching an existing store requires delete + recreate (options are baked in
at creation).

## BiometricVaultPluginException codes

| Code | Cause | Fix |
|---|---|---|
| `SecurityError` + message `-34018: A required entitlement isn't present.` | macOS app lacks signing and/or the Keychain Sharing capability (auth stores use the data-protection keychain) | Xcode -> Signing & Capabilities -> add Keychain Sharing (Debug AND Release entitlements) |
| `SecurityError` (other OSStatus) | Darwin keychain error; message carries the status and description | Inspect the status code |
| `NoSuchStorage` | `read`/`write`/`delete` before `getStorage` for that name in this process (e.g. after hot-restart-sensitive caching or engine restart) | Always obtain the file from `getStorage` first |
| `AlreadyInitialized` | `getStorage(name, forceInit: true)` when the store already exists in this process | Drop `forceInit` or restructure init |
| `Unsupported` | `authenticate()` on Linux/Windows/web | Gate with `canAuthenticate()` first |
| `Bad Arguments` + "Linux plugin only supports non-authenticated secure storage" | Store created without `authenticationRequired: false` on Linux | Create Linux stores with `authenticationRequired: false` |
| `MissingArgument` / `InvalidArguments` | Wire-level misuse; effectively unreachable through the public API | Report a bug |
| `Unexpected Error` | Uncaught native exception; details carry the native stack | Report a bug with details |
| `ReadError`/`WriteError`/`DeleteError` | Windows Credential Manager failures (message carries Win32 error) | Inspect message |
| `RetrieveError` | Darwin keychain returned non-UTF-8/unexpected data | Report a bug |

`ArgumentError` (not a `BiometricVaultException`) at `getStorage`: empty
name or path separators in the name, or `androidBiometricOnly: false`
without `androidAuthenticationValidityDuration`.

## CanAuthenticateResponse quick map

`success` proceed; `statusUnknown` (Android) attempt and handle failure;
`errorNoBiometricEnrolled` guide enrollment (with `androidBiometricOnly:
false` and no device credential either, Android reports
`errorPasscodeNotSet` instead); `errorLockedOut` (iOS/macOS only from the
capability check; Android cannot report lockout here - it surfaces at
prompt time) clears via passcode auth; `errorHwUnavailable` retry later -
and it is the PERMANENT answer on Linux/Windows/web (registered fallback
backends) plus disconnected Touch ID keyboards on macOS; `errorNoHardware`
no sensor (macOS: no built-in or paired Touch ID);
`errorSecurityUpdateRequired` Android sensor disabled pending update;
`unsupported` only from embedders without any registered implementation.

## Diagnostics

- Android native log: `adb shell setprop log.tag.BiometricVault DEBUG`
  then `adb logcat -s BiometricVault` (warnings/errors log without the
  prop). The "not a FragmentActivity" line settles most `failedToStart`
  reports.
- iOS/macOS native log: subsystem `biometric_vault`, e.g.
  `log stream --predicate 'subsystem == "biometric_vault"' --level info`
  (macOS) or Console.app filtered to the subsystem (iOS device).
- iOS SIMULATOR does not enforce keychain access control: gated reads
  succeed without any prompt even when unenrolled. Never diagnose
  prompt/lockout behavior on the simulator; `canAuthenticate` DOES reflect
  simulator enrollment.
- Value became `null` after an app update: check whether the update toggled
  `silentWrites` for an existing store name - the Android backing file
  changes (`.v2.txt` vs `.v3.txt`) and the old value is orphaned. Options
  must never change for an existing store name without delete + recreate.
- On iOS/macOS a NON-silent write to an existing gated item prompts (the
  update path evaluates access control); only `silentWrites: true` writes
  are prompt-free by design.
