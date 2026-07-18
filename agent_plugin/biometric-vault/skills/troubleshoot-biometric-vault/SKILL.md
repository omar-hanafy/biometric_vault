---
name: troubleshoot-biometric-vault
description: Use when an app using the biometric_vault Flutter package misbehaves at runtime - AuthException codes such as failedToStart or lockedOut, StorageInvalidatedException after users change biometric enrollment, SecurityError -34018 on macOS, reads returning null unexpectedly, prompts not appearing or appearing twice, silent-writes stores where writes succeed while reads keep failing, or biometric flows that behave differently on the iOS simulator than on real devices. Not for first-time package setup (use integrate-biometric-vault) and not for converting an app from biometric_storage (use migrate-from-biometric-storage).
---

# Troubleshooting biometric_vault

Every failure this package reports is a subtype of the sealed
`BiometricVaultException` with a precise typed code, and almost every code
has exactly one root cause. Diagnose from the code, not from vibes:
[references/error-codes.md](references/error-codes.md) is the complete
symptom -> cause -> fix table. Do not guess causes that the table already
pins down, and do not read the plugin's native sources when the table
answers the question.

## Workflow

1. **Pin the exact failure.** Get the runtime type (`AuthException` /
   `StorageInvalidatedException` / `BiometricVaultPluginException`) and its
   `code`/`reason`, plus platform, plugin version, and whether it happens on
   a simulator or device. If the report only says "it fails", have the
   caller log `e.toString()` - it contains the typed code.
2. **Look the code up** in [references/error-codes.md](references/error-codes.md)
   and read the matching row/section fully before proposing anything.
3. **Confirm the cause in the project**, not from memory. The frequent ones:
   - `failedToStart` (Android): inspect the shipped variant's
     `MainActivity` (must extend `FlutterFragmentActivity`), manifest
     activity entries, theme parents (`Theme.AppCompat` in `values/` AND
     `values-night/`), and whether the call runs in a background isolate.
   - `SecurityError` -34018 (macOS): check `DebugProfile.entitlements` /
     `Release.entitlements` for `keychain-access-groups` and that signing is
     enabled.
   - `StorageInvalidatedException`: ask what changed on the device
     (enrollment) and how the app reacts today - the recovery MUST be
     `delete()` -> re-authenticate the user -> `write()`. On silent-writes
     stores, `write()` without `delete()` does not heal anything even
     though it succeeds.
   - Unexpected `null` reads after an update: check whether store OPTIONS
     changed for an existing store name (options are fixed at first
     creation; toggling `silentWrites` switches the Android backing file
     and orphans the old value).
4. **Check the environment before declaring a bug.** The iOS simulator does
   not enforce keychain access control (gated reads succeed with no
   prompt); Android lockout clears by itself (~30 s) or via device
   credential; macOS Touch ID keyboards disconnect.
5. **Capture native logs when the Dart-side evidence is thin** - exact
   commands are at the bottom of the reference (Android tag
   `BiometricVault`, darwin subsystem `biometric_vault`).
6. **Apply the smallest fix, then validate**: `dart format` on changed
   files, `flutter analyze`, run the app flow (or the relevant tests) that
   reproduced the failure. Report what was wrong, why, and what to tell
   affected users (e.g. invalidated values are unrecoverable by design -
   users must sign in again; that is not data corruption).

## The five production classics

| Report | Almost always |
|---|---|
| "failedToStart though fingerprint works in other apps" | `FlutterActivity` instead of `FlutterFragmentActivity` (or background isolate); never a sensor problem |
| "Users logged out after adding a fingerprint" | Keystore invalidation by design; app lacks the delete -> re-auth -> write recovery |
| "Writes work, reads fail" on a silent-writes store | Same invalidation; the RSA public (write) half survives - `delete()` first, then rewrite |
| "-34018" on macOS | Missing Keychain Sharing capability / signing |
| "No prompt appears on iOS" | Simulator - access control is not enforced there; test on a device |

## Boundaries

- Fixes stay in the consumer app. If the evidence truly points at a plugin
  bug (e.g. `Unexpected Error` with a native stack, `RetrieveError`),
  collect the typed exception, native log lines, and a minimal repro, and
  file it at https://github.com/omar-hanafy/biometric_vault/issues instead
  of patching around it.
- Never "fix" a failure by setting `authenticationRequired: false` unless
  the user explicitly accepts removing the authentication gate.
- Invalidated data cannot be recovered by any code path; do not promise
  otherwise.
