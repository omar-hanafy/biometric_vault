# Per-platform setup for biometric_vault

Facts below come from the plugin's native sources. Baseline: Flutter 3.44+ /
Dart 3.12+, biometric_vault ^1.1.0.

## Android (API 24+)

No manifest changes: the plugin's own manifest declares `USE_BIOMETRIC` (and
`USE_FINGERPRINT` up to API 27), which Gradle merges into the app.

Two host-app requirements, both commonly missing from default Flutter
templates:

1. **The activity MUST be a `FlutterFragmentActivity`.** `BiometricPrompt`
   requires a `FragmentActivity`; with the default `FlutterActivity`, every
   authenticated operation and `authenticate()` fails with
   `AuthException(AuthExceptionCode.failedToStart)` at runtime (no
   compile-time signal).

   `android/app/src/main/kotlin/<package>/MainActivity.kt`:

   ```kotlin
   import io.flutter.embedding.android.FlutterFragmentActivity

   class MainActivity : FlutterFragmentActivity()
   ```

2. **The activity theme must inherit from `Theme.AppCompat`.** The default
   template inherits `@android:style/...` themes; the biometric prompt then
   crashes. Update BOTH `values/styles.xml` and `values-night/styles.xml`:

   ```xml
   <style name="LaunchTheme" parent="Theme.AppCompat.NoActionBar">
   ```

   (keep each style's existing `<item>` entries; only the `parent` changes).
   `NormalTheme` needs the same parent.

Behavior notes:

- Device-credential fallback (`androidBiometricOnly: false`) requires
  Android 11 (API 30); below that the plugin logs and ignores the fallback.
- Keys are hardware-backed: StrongBox when the device has it, TEE otherwise
  (automatic fallback).

## iOS (13+)

- Add `NSFaceIDUsageDescription` to `ios/Runner/Info.plist`. Without it, iOS
  terminates the app the first time Face ID is evaluated:

  ```xml
  <key>NSFaceIDUsageDescription</key>
  <string>Unlocks your stored credentials.</string>
  ```

- Nothing else: the plugin ships as a Swift package (CocoaPods also
  supported); `LocalAuthentication`/`Security` are linked by the plugin.
- **Simulator warning:** the iOS simulator keychain does not enforce
  `kSecAttrAccessControl`. Reads and writes on authentication-required stores
  succeed without any Face ID sheet, even with no enrollment. Never conclude
  the gate works (or is broken) from simulator behavior; verify prompts on a
  physical device. `canAuthenticate()` DOES reflect simulator enrollment
  state, so capability handling is testable there.

## macOS (10.15+)

- **Signing plus the Keychain Sharing capability are required** for
  authentication-gated stores (the plugin uses the data-protection keychain).
  Without them, operations fail with `BiometricVaultPluginException` code
  `SecurityError` and message containing `-34018: A required entitlement
  isn't present.` In Xcode: Runner target -> Signing & Capabilities -> add
  "Keychain Sharing" (repeat for Debug and Release; it writes
  `keychain-access-groups` with
  `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` into
  `DebugProfile.entitlements` and `Release.entitlements`). A real signing
  team must be selected for `$(AppIdentifierPrefix)` to resolve.
- Add `NSFaceIDUsageDescription` to `macos/Runner/Info.plist` when using
  biometrics.
- Touch ID hardware states are reported precisely: no built-in or paired
  Touch ID -> `CanAuthenticateResponse.errorNoHardware`; a Touch ID keyboard
  that is currently disconnected -> `errorHwUnavailable`.

## Linux

- **Stores MUST be created with `authenticationRequired: false`.** The native
  side rejects `init` for authenticated stores ("Linux plugin only supports
  non-authenticated secure storage"). `canAuthenticate()` reports
  `errorHwUnavailable`, which is the branch signal.
- Values go to the Secret Service (libsecret / GNOME Keyring). Build needs
  `libsecret-1-dev` (plus the usual `ninja-build libgtk-3-dev`); runtime
  needs a keyring daemon.
- Inside a snap, AppArmor may deny the Secret Service. Probe with
  `BiometricVault().linuxCheckAppArmorError()`; the fix is connecting the
  snap's `password-manager-service` plug.

## Windows

- Values are stored in the Windows Credential Manager (encrypted for the OS
  user, visible in its UI, prefixed `io.github.omarhanafy.authpass.`). There
  is NO authentication gate; `canAuthenticate()` reports
  `errorHwUnavailable`. No configuration needed.

## Web

- Values are stored as **plaintext in `localStorage`**. This backend exists
  only so cross-platform code keeps running during development; never treat
  it as secure storage for real secrets. `canAuthenticate()` reports
  `errorHwUnavailable`.

## Capability gate used on every platform

```dart
final support = await BiometricVault().canAuthenticate(options: options);
final canGate = support == CanAuthenticateResponse.success ||
    support == CanAuthenticateResponse.statusUnknown; // Android: try anyway
```

When `canGate` is false, decide per product: block the feature, direct the
user to enroll (`errorNoBiometricEnrolled`), or fall back to a store created
with `authenticationRequired: false` (still keystore-encrypted, but any code
in the app can read it without a prompt). On Linux/Windows/web this fallback
is the only option.
