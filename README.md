# biometric_vault

[![Pub](https://img.shields.io/pub/v/biometric_vault?color=green)](https://pub.dev/packages/biometric_vault/)
[![CI](https://github.com/omar-hanafy/biometric_vault/actions/workflows/ci.yml/badge.svg)](https://github.com/omar-hanafy/biometric_vault/actions/workflows/ci.yml)

Encrypted storage for small secrets (tokens, passwords, key material) with
optional biometric protection. Secrets are encrypted by the platform keystore
and, when you ask for it, unlocked only after Face ID / Touch ID /
fingerprint / device-credential authentication.

## Highlights

- **Typed errors, no surprises.** Every failure is a subtype of the sealed
  `BiometricVaultException`; one `switch` handles all outcomes exhaustively.
  Raw `PlatformException`s never escape.
- **Hardware-backed encryption.** Android Keystore (StrongBox when available,
  TEE fallback) with AES-GCM; iOS/macOS Keychain with `SecAccessControl`.
- **Precise capability reporting.** `canAuthenticate()` tells you exactly why
  authentication is unavailable: nothing enrolled, no hardware, locked out,
  pending security update, and more. `biometryType()` tells you what to call
  it in your UI: Face ID, Touch ID, fingerprint, and friends.
- **Silent writes for rotating secrets.** With
  `StorageFileInitOptions(silentWrites: true)` writes never prompt (envelope
  encryption on Android, replace-on-write on iOS/macOS) while reads stay
  fully gated. Persist a rotated refresh token from a background refresh
  without interrupting anyone.
- **Standalone authentication.** `authenticate()` shows the system prompt
  without touching any storage, for app-lock style privacy gates.
- **Fail-fast validation.** Invalid store names or impossible option
  combinations throw `ArgumentError` at `getStorage`, not a native error at
  first use in production.
- **Modern toolchains.** Swift Package Manager on iOS/macOS (CocoaPods still
  supported), Built-in Kotlin and Gradle Kotlin DSL on Android, and a
  UI-thread-free native implementation on every platform.

This package stores small secrets, not large datasets. Store a key or token
in `biometric_vault` and encrypt your bulk data with it.

## Platform support

| Platform | Backing store | Authentication gate |
|---|---|---|
| Android 7.0+ (API 24) | AES-GCM key in the Android Keystore (StrongBox when available, TEE fallback) | BiometricPrompt: Class 3 biometrics, optional device credential fallback |
| iOS 13+ | Keychain with access control | Face ID / Touch ID, optional passcode fallback |
| macOS 10.15+ | Keychain with access control | Touch ID / Apple Watch, optional password fallback |
| Linux | libsecret keyring | none |
| Windows | Credential Manager | none |
| Web | plaintext `localStorage`, **not secure** | none |

Release baseline: Flutter `3.44` / Dart `3.12`.

## Getting started

Add the dependency:

```yaml
dependencies:
  biometric_vault: ^1.1.0
```

### Android

- Android 7.0 (API level `24`) or newer.
- The host activity must extend `FlutterFragmentActivity`, otherwise every
  authenticated operation fails with `AuthExceptionCode.failedToStart`.
- The activity theme must inherit from `Theme.AppCompat`.

**android/app/src/main/kotlin/.../MainActivity.kt**

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

**android/app/src/main/res/values/styles.xml**

```xml
<resources>
  <style name="LaunchTheme" parent="Theme.AppCompat.NoActionBar" />
  <style name="NormalTheme" parent="Theme.AppCompat.NoActionBar" />
</resources>
```

### iOS

- Include the `NSFaceIDUsageDescription` key in your app's `Info.plist`;
  without it, iOS terminates the app when Face ID is first used.

**Known issue**: local authentication in the iOS simulator is unreliable on
recent iOS versions; test biometric flows on a real device.
https://developer.apple.com/forums/thread/685773

### macOS

- Include the `NSFaceIDUsageDescription` key in your app's `Info.plist` if
  you rely on biometrics.
- Enable signing and the Keychain Sharing capability for the host app.
  Without it you will see a `BiometricVaultPluginException` with code
  `SecurityError` and message `-34018: A required entitlement isn't present.`

### Linux, Windows, and web

- Linux and Windows store values through the OS (libsecret / Credential
  Manager) without any authentication prompt; `canAuthenticate` reports
  `errorHwUnavailable` there.
- Web stores plaintext values in browser `localStorage`. Do not treat the
  web implementation as secure storage; it exists so cross-platform code
  keeps working during development.

## Usage

You only need four calls for the whole lifecycle:

```dart
import 'package:biometric_vault/biometric_vault.dart';

// 1. Check what the device supports.
final support = await BiometricVault().canAuthenticate();
if (support != CanAuthenticateResponse.success &&
    support != CanAuthenticateResponse.statusUnknown) {
  // Inspect the value: no hardware, nothing enrolled, locked out, ...
  return;
}

// 2. Open (or create) a named store.
final store = await BiometricVault().getStorage('my_token');

// 3. Write a value (may show the system authentication prompt).
await store.write('my secret');

// 4. Read it back (may prompt again, depending on the options).
final value = await store.read(); // null when nothing was stored
```

### Options

Options are applied when a store is first created; see
`StorageFileInitOptions` for the full documentation of each flag.

```dart
final store = await BiometricVault().getStorage(
  'my_token',
  options: StorageFileInitOptions(
    // One authentication unlocks the store for 30 seconds (Android).
    androidAuthenticationValidityDuration: Duration(seconds: 30),
    // Allow PIN/pattern/password fallback (requires the duration above).
    androidBiometricOnly: false,
    // Allow the device passcode as fallback on iOS/macOS.
    darwinBiometricOnly: false,
    // Reuse one authenticated context for 30 seconds (iOS/macOS).
    darwinTouchIDAuthenticationForceReuseContextDuration:
        Duration(seconds: 30),
  ),
  promptInfo: const PromptInfo(
    androidPromptInfo: AndroidPromptInfo(title: 'Unlock your vault'),
    iosPromptInfo: DarwinPromptInfo(accessTitle: 'Unlock your vault'),
  ),
);
```

Set `authenticationRequired: false` to store values through the platform
keystore without any authentication prompt (useful as a fallback when
`canAuthenticate` reports that biometry is unavailable).

### Silent writes

For secrets that rotate while the app runs (refresh tokens, session keys),
create the store with `silentWrites: true`: every `write()` completes without
any prompt, while `read()` keeps requiring authentication.

```dart
final tokenStore = await BiometricVault().getStorage(
  'refresh_token',
  options: StorageFileInitOptions(silentWrites: true),
);

await tokenStore.write(rotatedToken); // never prompts
final token = await tokenStore.read(); // prompts as usual
```

On Android this uses envelope encryption: the payload is encrypted with a
fresh AES-256-GCM key that is wrapped by a Keystore RSA public key, and only
the private (read) half requires user authentication. On iOS and macOS the
write replaces the keychain item, which never evaluates its access control.

One consequence worth knowing: after the user changes biometric enrollment,
reads throw `StorageInvalidatedException` as usual, but writes keep working,
so your next sign-in can silently re-provision the secret.

### Biometry labels and app-lock gates

`biometryType()` reports the device's biometry modality so UI copy can say
"Face ID" instead of a generic "biometrics" (and not say "Face ID" on a
Touch ID device):

```dart
final label = switch (await BiometricVault().biometryType()) {
  BiometryType.faceId => 'Face ID',
  BiometryType.touchId => 'Touch ID',
  BiometryType.fingerprint => 'Fingerprint',
  _ => 'Biometrics',
};
```

`authenticate()` shows the system prompt without touching any storage, which
is exactly what an app-lock privacy gate needs (proof of presence, no key
material):

```dart
try {
  await BiometricVault().authenticate(); // device credential fallback allowed
  unlockTheUi();
} on AuthException catch (e) {
  // e.code says what happened: userCanceled, lockedOut, ...
}
```

### Error handling

Every failure is a subtype of the sealed `BiometricVaultException`, so a
single `switch` handles all outcomes exhaustively:

```dart
try {
  final value = await store.read();
} on BiometricVaultException catch (e) {
  switch (e) {
    case AuthException(code: AuthExceptionCode.userCanceled):
      break; // The user knows they canceled; no error UI needed.
    case AuthException(code: AuthExceptionCode.lockedOut):
      showSnackBar('Too many attempts. Try again in a few seconds.');
    case AuthException(code: AuthExceptionCode.lockedOutPermanently):
      showSnackBar('Biometry locked. Unlock your device with PIN first.');
    case AuthException(:final code):
      showSnackBar('Authentication failed: $code');
    case StorageInvalidatedException():
      // The value is permanently unrecoverable, for example after the user
      // changed biometric enrollment on Android. Re-provision the secret.
      await store.delete();
      await promptUserToSignInAgain();
    case BiometricVaultPluginException(:final code):
      reportToCrashlytics('biometric_vault error $code: ${e.message}');
  }
}
```

`AuthException` means the user could not or did not authenticate; the stored
data is untouched and the call can be retried. `StorageInvalidatedException`
means the data is gone for good. `BiometricVaultPluginException` wraps
unexpected platform errors and preserves the raw `code` and `details`.

## Resources

- API documentation: https://pub.dev/documentation/biometric_vault/latest/
- Android data security: https://developer.android.com/topic/security/data
- Apple keychain + biometry: https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id

## Credits and license

MIT licensed. `biometric_vault` began as a fork of
[`biometric_storage`](https://github.com/authpass/biometric_storage) by
Herbert Poul and was rebuilt from the ground up; the original copyright is
preserved in the [LICENSE](LICENSE) alongside the current maintainer's.
`biometric_vault` is an independent package: it registers its own platform
channel and its own native storage, and does not read values stored by
`biometric_storage`.
