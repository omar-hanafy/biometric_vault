Grade the response against these criteria. Score 1.0 only if ALL critical
criteria are met; deduct proportionally otherwise.

Critical:

1. PROACTIVELY surfaces that biometric_vault cannot read data stored by
   biometric_storage (independent channel and native storage), so without
   an in-app data migration every existing user's token is lost (logout for
   millions of users). The prompt deliberately does not mention data
   preservation - a migration plan that just swaps the API and drops the
   stored tokens (or never mentions the issue) scores at most 0.3.
2. Keeps BOTH packages installed during the migration window and migrates
   lazily at runtime: read the legacy biometric_storage value, write it
   into the biometric_vault store, and only delete the legacy copy AFTER
   the new write succeeded (write-then-delete ordering stated or shown in
   code). User cancellation must leave the legacy data intact (retry next
   time).
3. Uses a DIFFERENT store name for the biometric_vault store than the
   legacy 'refresh_token' name (or explicitly warns that reusing the same
   name shares the Android Keystore alias `_CM_<name>_master_key` between
   the two packages, so deleting the legacy store would destroy the
   migrated value). Reusing the same name with no mention of this FAILS
   the criterion.
4. Maps the deprecated authenticationValidityDurationSeconds correctly:
   androidAuthenticationValidityDuration for Android (keeping
   androidBiometricOnly: false valid, since that combination requires the
   duration), and addresses the darwin side explicitly (allowable-reuse vs
   force-reuse-context distinction, or asks which behavior is intended).
5. Updates error handling for the new model: mentions
   StorageInvalidatedException (and its delete + re-provision recovery)
   and/or the richer AuthExceptionCode set replacing the old 5-value enum.

Secondary:

6. Mentions IosPromptInfo -> DarwinPromptInfo (or type renames generally).
7. Plans eventual removal of the biometric_storage dependency only after
   users have migrated (e.g. a later release), or an explicit cleanup
   strategy.
8. Notes new capabilities (authenticate(), biometryType(), silentWrites)
   only as options, without forcing them into the migration.
