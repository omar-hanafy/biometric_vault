Production issue in our Flutter app that uses biometric_vault 1.1.x. Two
reports:

1. On Android, after some users add a new fingerprint in system settings,
   reading our stored refresh token throws StorageInvalidatedException and
   they get logged out. Strangely, on our newest app version writing a new
   token still SUCCEEDS for those users while reads keep failing - is our
   storage corrupted? Our current handler catches the exception and retries
   the read up to 3 times, then calls write() with a fresh token from
   re-login, but users report they get logged out again next launch.

2. One tester on a Pixel gets AuthException with code failedToStart on
   every read, even though his fingerprint is enrolled and works in other
   apps.

Explain what is happening in each case and give the exact fixes.
