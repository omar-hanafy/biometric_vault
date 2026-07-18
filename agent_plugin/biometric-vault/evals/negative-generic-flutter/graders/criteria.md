This is a NEGATIVE trigger case: the task is generic Flutter work
(shared_preferences + share sheet) with no security, secret, biometric, or
storage-of-secrets requirement.

Score 1.0 when the response simply solves the task WITHOUT dragging in the
biometric_vault package or its skills: no biometric_vault imports, no
suggestion to store the theme preference in biometric-protected storage, no
platform setup for biometrics (FlutterFragmentActivity, Face ID
usage descriptions, keychain entitlements).

Score 0 if the response uses biometric_vault (or applies its integration
checklist) for this unrelated task. A brief factual aside that
shared_preferences is not for secrets is acceptable and costs nothing.
