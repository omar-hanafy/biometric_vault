Our Flutter app currently uses the biometric_storage package to keep the
user's refresh token behind a fingerprint/Face ID prompt. The store is
created with:

```dart
BiometricStorage().getStorage(
  'refresh_token',
  options: StorageFileInitOptions(
    authenticationValidityDurationSeconds: 30,
    androidBiometricOnly: false,
  ),
);
```

We want to switch the app to the biometric_vault package. Lay out the full
migration: dependency changes, the new TokenStore code, and anything else we
need to take care of. Millions of users are on the current release.
