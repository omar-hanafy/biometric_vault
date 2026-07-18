I have a Flutter app (Android, iOS and macOS) and I need to store the user's
refresh token so it can only be read after Face ID / Touch ID / fingerprint
authentication, using the biometric_vault package. Write the complete
TokenStore service class for lib/token_store.dart, and tell me exactly what
else I must change anywhere in the project for this to work correctly in
production on all three platforms. Our token is rotated by a background
refresh while the app runs, and users must not be interrupted by prompts
when that happens.
