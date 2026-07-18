---
name: migrate-from-biometric-storage
description: Use when a Flutter app that currently uses the biometric_storage package (by authpass / Herbert Poul) should switch to biometric_vault - replacing the dependency, converting BiometricStorage/BiometricStorageFile/IosPromptInfo code, or when stored secrets from biometric_storage must survive the switch. Also applies when biometric_vault reads return null after such a switch. Not for fresh integrations without biometric_storage history (use integrate-biometric-vault).
---

# Migrating from biometric_storage to biometric_vault

biometric_vault began as a rewrite of biometric_storage, so the API shapes
are close - but the two packages CANNOT read each other's stored data
(independent method channels, keychain services, and file locations). A
pure API swap ships a silent logout/data-loss to every existing user.

**Data first, API second.** Before touching code, establish whether any
release of this app ever stored secrets with biometric_storage that users
still need (session/refresh tokens, keys, passwords). If yes - or if
unknown - the in-app data migration below is mandatory. Only a never-shipped
app or explicitly disposable data justifies a plain swap; state that
decision and its reason in your summary.

The complete old->new API table, the options mapping (including the
deprecated `authenticationValidityDurationSeconds`), and the native
storage-independence matrix are in
[references/api-mapping.md](references/api-mapping.md). Read it before
converting code.

## Data-preserving migration protocol

1. **Keep BOTH dependencies installed** during the migration window
   (`biometric_storage` and `biometric_vault` coexist cleanly; import the
   legacy package with a prefix: `import 'package:biometric_storage/...'
   as legacy;`). The legacy dependency is removed only in a later release,
   after this migration code has been in users' hands.
2. **Pick a NEW store name for the vault store** - never reuse the legacy
   name. Both packages derive the Android Keystore alias
   `_CM_<name>_master_key` from the store name; with the same name the
   vault would encrypt with the legacy package's key, and deleting the
   legacy store later would destroy that shared key and the migrated
   value with it. `refresh_token` -> `refresh_token_v2` is the pattern.
3. **Migrate lazily at first read**, inside the app's storage service:
   1. Read the vault store; a value means steady state - done.
   2. On `null`, read the legacy store (this shows the same single prompt
      the old app showed; map the legacy options faithfully so it opens
      exactly as before).
   3. Write the value into the vault store, and only AFTER that write
      succeeds, delete the legacy copy. This ordering means a crash,
      cancellation, or failure at any point leaves the secret readable
      and the migration retries next launch.
   4. User canceled the legacy read -> return the same "not authenticated"
      result the app already handles; legacy data stays put.
4. **Handle the richer error model while converting** (see the mapping
   reference): the old package reported most failures as
   `AuthExceptionCode.unknown`; the vault has 14 specific codes plus
   `StorageInvalidatedException`, whose recovery (delete -> re-auth ->
   write) the app almost certainly lacks. `clear()`/logout paths must
   delete BOTH stores while the legacy dependency remains.
5. **Prompt-count note:** the migration read prompts once (as the old app
   did). The follow-up vault write does not add a second prompt when the
   vault store is created with a validity/reuse window covering it, when
   `silentWrites: true`, or on iOS/macOS where the first write is a
   keychain add (access control is not evaluated on add).

## Conversion checklist (API swap part)

- `BiometricStorage()` -> `BiometricVault()`; `BiometricStorageFile` ->
  `BiometricVaultFile`; `IosPromptInfo` -> `DarwinPromptInfo`;
  `BiometricStorageException` -> `BiometricVaultPluginException`.
- Options: same field names in 5.1.x; the 5.0.x
  `authenticationValidityDurationSeconds: N` needs the per-platform split
  described in the reference (Android duration is mechanical; the darwin
  half is a judgment call - ask which behavior is wanted, or default to
  `darwinTouchIDAuthenticationForceReuseContextDuration` and say so).
- `androidBiometricOnly: false` still requires the Android validity
  duration; the vault now enforces this with an `ArgumentError` at
  `getStorage`.
- Exhaustive-switch error handling over the sealed hierarchy replaces
  old `if (e.code == ...)` chains.

## Validate

`dart format` changed files, `flutter analyze`, `flutter test` (the fake
in the test-with-biometric-vault skill can simulate both stores' behavior
for migration tests). Walk through the migration state machine once more
against these cases before finishing: fresh install (no legacy data),
normal migration, user cancels, crash between write and legacy delete,
legacy store already empty, vault value later invalidated. Summarize for
the user: what migrates when, what users will see (one prompt), when the
legacy dependency can be dropped, and any judgment calls made.
