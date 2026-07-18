---
name: integrate-biometric-vault
description: Use when adding the biometric_vault Flutter package to an app or wiring a feature on top of it - storing tokens, passwords, or keys behind Face ID / Touch ID / fingerprint / device-credential authentication, building an app-lock gate, choosing StorageFileInitOptions, or setting the package up for Android, iOS, macOS, Linux, Windows, or web. Not for debugging an existing integration that fails at runtime (use troubleshoot-biometric-vault) and not for converting an app from the biometric_storage package (use migrate-from-biometric-storage).
---

# Integrating biometric_vault

Correct integration is 20% Dart and 80% knowing the platform contracts.
The Dart code compiles fine while the app fails on device when host-app
setup is missing, so NEVER skip step 3. Do not re-derive platform behavior
from the plugin's native sources; the two references contain the verified
facts:

- [references/platform-setup.md](references/platform-setup.md) - required
  host-app changes per platform and per-platform storage behavior.
- [references/options.md](references/options.md) - what every
  `StorageFileInitOptions` flag does, invalid combinations, and presets.

## Workflow

1. **Inspect the project first.** Package version in pubspec (skills assume
   1.1.x; `silentWrites`, `biometryType()` and `authenticate()` need
   >= 1.1.0), enabled platforms, existing `MainActivity`, styles, plists,
   entitlements, and any existing secure-storage usage. Add the dependency
   with `flutter pub add biometric_vault` if missing.
2. **Pin the use case, then pick options from the matrix** in
   [references/options.md](references/options.md). The decisions that
   matter: does anything write while the user is not interacting
   (-> `silentWrites: true`); is passcode/PIN fallback acceptable
   (-> `*BiometricOnly: false`, on Android REQUIRES a validity duration);
   how often reads happen (-> reuse durations); is this just an app-lock
   gate (-> `authenticate()`, no store at all). Remember: options are
   FIXED once a store name exists - changing them later needs delete +
   recreate + re-provision.
3. **Apply the platform setup** from
   [references/platform-setup.md](references/platform-setup.md) for every
   platform the app enables. Android `FlutterFragmentActivity` +
   `Theme.AppCompat` (both `values/` and `values-night/`), iOS
   `NSFaceIDUsageDescription`, macOS Keychain Sharing entitlements +
   signing + usage description, Linux `authenticationRequired: false`
   branch. Make the edits; do not just tell the user to do them.
4. **Write the service wrapper** (one class owning the store), gated by
   `canAuthenticate(options: <the same options>)`:

   ```dart
   final support = await BiometricVault().canAuthenticate(options: options);
   final usable = support == CanAuthenticateResponse.success ||
       support == CanAuthenticateResponse.statusUnknown;
   ```

   Create the store once (`getStorage(name, options: ..., promptInfo: ...)`)
   and reuse the returned file. Set `PromptInfo` texts that tell the user
   WHY - exact constructor shape (note: the iOS and macOS slots are both
   `DarwinPromptInfo`):

   ```dart
   promptInfo: const PromptInfo(
     androidPromptInfo: AndroidPromptInfo(title: 'Unlock your vault'),
     iosPromptInfo: DarwinPromptInfo(accessTitle: 'Unlock your vault'),
     macOsPromptInfo: DarwinPromptInfo(accessTitle: 'Unlock your vault'),
   ),
   ```

   Use `biometryType()` when UI copy names the authenticator (say
   "Face ID" only on Face ID hardware).
5. **Handle the sealed error contract exhaustively** - this is where
   integrations rot in production:

   ```dart
   try {
     final value = await store.read();
   } on BiometricVaultException catch (e) {
     switch (e) {
       case AuthException(code: AuthExceptionCode.userCanceled):
         // No error UI; data intact, retry later.
       case AuthException(code: AuthExceptionCode.lockedOut):
         // Temporary; offer retry (Android ~30s; darwin clears via passcode).
       case AuthException(:final code):
         // Show reason; data intact.
       case StorageInvalidatedException():
         // PERMANENT (e.g. user re-enrolled biometrics on Android).
         await store.delete();          // required BEFORE re-provisioning
         // -> sign the user in again, then write() the fresh secret.
       case BiometricVaultPluginException(:final code):
         // Integration/platform bug: report with code + message.
     }
   }
   ```

   Never swallow `StorageInvalidatedException` into a retry loop, and
   never "recover" by recreating the store with
   `authenticationRequired: false` (that silently removes the gate).
6. **Validate**: `dart format` on changed files, `flutter analyze`,
   `flutter test`. Remind the user that prompt behavior must be verified
   on a real iOS device (the simulator does not enforce the gate) and that
   macOS needs a signing team selected for the keychain entitlement to
   resolve.

## Boundaries and defaults

- Secure by default: keep `authenticationRequired: true` unless the user
  explicitly wants unauthenticated keystore storage; call out the security
  meaning whenever it is `false`.
- This package stores SMALL secrets (strings). For bulk data, store a key
  here and encrypt the data with it.
- One store per secret with distinct names beats one JSON blob when
  protection needs differ.
- If web is a target, state clearly that the web backend is plaintext
  `localStorage` and must not hold real secrets.
- Missing information that changes the design (target platforms, whether
  background writes happen, fallback policy) - ask, do not guess.
