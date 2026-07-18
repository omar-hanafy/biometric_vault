Grade the response against these criteria. Score 1.0 only if ALL critical
criteria are met; deduct proportionally otherwise.

Critical:

1. The tests fake the PLATFORM INTERFACE: a class extending BiometricVault
   (via the public `BiometricVault.create()` super constructor, or an
   equivalent documented mock with MockPlatformInterfaceMixin) installed
   through the `BiometricVault.instance` setter.
2. Does NOT mock MethodChannel('biometric_vault') and does NOT hard-code
   the plugin's internal wire strings ('AuthError:UserCanceled',
   'StorageError:KeyInvalidated', method names 'init'/'read'/'write') or
   use debugDefaultTargetPlatformOverride to force the channel path. Any of
   those appearing in the produced tests FAILS this criterion (they couple
   consumer tests to the plugin's internal protocol).
3. Failure scenarios are scripted with the package's REAL public exception
   types: AuthException(AuthExceptionCode.userCanceled, ...) and
   StorageInvalidatedException(StorageInvalidatedReason..., ...).
4. The invalidation test asserts BOTH that null is returned AND that the
   store's delete was invoked (observable through the fake).
5. All four requested scenarios are covered (happy read, canceled read,
   invalidation recovery, write pass-through).

Secondary:

6. Fresh fake installed per test (setUp), and the response notes how to
   restore the real implementation (MethodChannelBiometricVault) if needed.
7. Mentions that prompt/authentication BEHAVIOR cannot be verified on the
   iOS simulator (device-only), or otherwise scopes what these unit tests
   prove.
