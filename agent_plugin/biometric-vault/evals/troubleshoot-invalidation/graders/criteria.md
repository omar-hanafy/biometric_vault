Grade the response against these criteria. Score 1.0 only if ALL critical
criteria are met; deduct proportionally otherwise.

Critical:

1. Case 1 root cause: Android Keystore permanently invalidates
   authentication-bound keys when biometric enrollment changes; this is
   platform behavior / by design, and the data is NOT corrupted.
2. Explains the write/read asymmetry via silent writes: writes use the RSA
   public (or "write") half which survives invalidation, while the
   auth-gated read/private half is dead.
3. Identifies the app's actual bug precisely: writing a fresh token WITHOUT
   calling delete() first does not recover the store - the new value is
   still encrypted for the invalidated key, so reads fail again. The fix is
   delete() FIRST, then re-authenticate/sign in, then write(). A response
   that only says "handle the exception" without the delete-first ordering
   FAILS this criterion. Also flags that retrying the read is pointless
   (permanent condition).
4. Case 2 root cause: failedToStart means the plugin has no FragmentActivity
   - MainActivity extends FlutterActivity instead of FlutterFragmentActivity
   (or the call runs without a foreground activity / background isolate).
   It is an integration bug, not a sensor/biometry problem.
5. Case 2 fix: MainActivity : FlutterFragmentActivity() plus
   Theme.AppCompat-derived theme; ideally suggests verifying via logcat tag
   BiometricVault or checking the shipped variant.

Secondary:

6. Mentions an option for tokens to survive enrollment changes (time-bound
   key via androidAuthenticationValidityDuration, requiring delete +
   recreate of the store) or the darwin equivalent - with the trade-off.
7. Does not recommend authenticationRequired: false as the fix.
8. Does not claim the invalidated value can be recovered.
