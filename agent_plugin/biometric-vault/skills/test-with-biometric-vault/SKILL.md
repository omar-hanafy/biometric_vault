---
name: test-with-biometric-vault
description: Use when writing or fixing Dart/Flutter tests for app code that uses the biometric_vault package - unit or widget tests that must run without a device or emulator, tests simulating authentication failures (user cancellation, lockout, storage invalidation), or tests failing with MissingPluginException on the biometric_vault channel. Not for testing the plugin's own native implementations.
---

# Testing app code that uses biometric_vault

## Core pattern: fake the platform interface, never the method channel

`BiometricVault` is a platform interface with a public extension seam
designed for exactly this: subclass it with `super.create()` and install
the fake via the `BiometricVault.instance` setter. App code that calls
`BiometricVault()` then transparently uses the fake - no injection
refactor, no device, no `MissingPluginException`.

Copy [references/fake_vault.dart](references/fake_vault.dart) into the
app's `test/` directory. It is a complete, compiling in-memory fake with
scriptable failures:

```dart
final vault = FakeBiometricVault();
BiometricVault.instance = vault;
vault.values['refresh_token'] = 'stored-token';

// Exercise a failure path:
vault.nextReadError = const AuthException(
  AuthExceptionCode.userCanceled, 'canceled');

// Assert the options your code created the store with:
expect(vault.capturedOptions['refresh_token']?.silentWrites, isTrue);
```

Do NOT mock the plugin's `MethodChannel('biometric_vault')` in consumer
tests. The channel method names, argument keys, and error strings
(`AuthError:*`, `StorageError:*`) are the plugin's INTERNAL wire protocol -
documented as such in its source - and channel mocks additionally need
`debugDefaultTargetPlatformOverride` hacks to reach the channel path. The
plugin's own test suite already covers the wire-to-exception mapping;
consumer tests should script the public exception types directly, as the
fake does.

## What is worth testing (from the package's error contract)

| Scenario | Script with |
|---|---|
| Value present / absent | seed `vault.values` / leave empty (`read()` yields `null`) |
| User cancels the prompt | `nextReadError = AuthException(AuthExceptionCode.userCanceled, ...)` - typically no error UI |
| Temporary lockout | `AuthExceptionCode.lockedOut` - retry/message path |
| Enrollment changed (permanent loss) | `nextReadError = StorageInvalidatedException(StorageInvalidatedReason.keyInvalidated, ...)` - code must delete + re-provision, never retry-loop |
| Device cannot authenticate | `canAuthenticateResponse = CanAuthenticateResponse.errorNoBiometricEnrolled` (etc.) - capability gate branch |
| App-lock gate outcomes | `nextAuthenticateError` for `authenticate()` failures |
| Store configured correctly | assert `capturedOptions[name]` |

Cover at minimum: the happy path, `userCanceled`, and the
`StorageInvalidatedException` recovery - the last one is where production
apps most often lack coverage and mis-handle permanent data loss.

## Mechanics and pitfalls

- Install the fake in `setUp` (a fresh fake per test); to hand control back
  to the real implementation, `BiometricVault.instance =
  MethodChannelBiometricVault();` (exported by the package).
- Mockito/mocktail users: a generated mock must
  `implement BiometricVault` WITH `MockPlatformInterfaceMixin` (from
  `plugin_platform_interface`) or the `instance` setter rejects it. The
  hand-written fake avoids that entirely by extending `BiometricVault`.
- The fake intentionally mirrors the real fail-fast `ArgumentError` for
  invalid store names, so bad names still fail in tests.
- Integration tests (`integration_test/`) on the iOS SIMULATOR cannot
  verify authentication gating: the simulator keychain does not enforce
  access control, so gated reads succeed without a prompt. Prompt behavior
  is device-only territory; keep it out of CI assertions.
- Never weaken the code under test to make it testable (e.g. do not switch
  the app to `authenticationRequired: false` for testability - the fake
  makes that unnecessary).

## Validate

Run `flutter test` and confirm the new tests pass and fail meaningfully
(temporarily break the code under test if unsure the assertions bite).
Format changed files with `dart format`.
