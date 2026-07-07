---
name: verify
description: Runtime verification recipe for biometric_vault - build, launch, and drive the plugin end to end on the iOS simulator with controllable biometry state.
---

# Verifying biometric_vault changes

The plugin is a library; its surface is the package boundary exercised by the
example app running on a device or simulator.

## Handle

```bash
cd example
flutter run -d <SIM_UDID> 2>&1 | tee /tmp/e2e_run.log   # VM service URI + app logs
```

Pick a simulator UDID from `xcrun simctl list devices | grep iPhone`.

## Driving flows

The example app has no automation package. The proven approach: temporarily
add an auto-run sequence in `MyAppState.initState` (postFrameCallback calling
the plugin APIs and logging results), run it, read the `flutter:` log lines,
then REVERT the patch. The StorageActions buttons have stable ValueKeys
(`<storeName>.read` / `.write` / `.delete`) if a tap driver is available.

## Simulator biometry control

`simctl ui <udid> biometry` does NOT exist in current Xcode. Use BiometricKit
notifications instead:

```bash
xcrun simctl spawn <UDID> notifyutil -s com.apple.BiometricKit.enrollmentChanged 1  # enroll
xcrun simctl spawn <UDID> notifyutil -p com.apple.BiometricKit.enrollmentChanged
# 0 instead of 1 to unenroll; relaunch the app afterwards.
```

## Known simulator limits

- The simulator keychain does NOT enforce `kSecAttrAccessControl`: reads and
  writes on authentication-required stores succeed without any Face ID sheet,
  even when unenrolled. Prompt, lockout, and errSecAuthFailed paths can only
  be observed on real hardware; they are pinned by the RunnerTests suite
  (fake keychain + fake LAContext).
- `canAuthenticate` DOES reflect enrollment state on the simulator, so the
  capability mapping is verifiable live (success vs errorNoBiometricEnrolled).

## Native suites (run after any Swift/Kotlin change)

```bash
cd example/ios   && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RunnerTests
cd example/macos && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -only-testing:RunnerTests
# Android (system JDK 26 breaks gradle; use the Android Studio JBR):
JAVA_HOME="/Users/omarhanafy/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  sh -c 'cd example/android && ./gradlew :biometric_vault:testDebugUnitTest'
```

If `xcodebuild` fails with `Module 'biometric_vault' not found`, regenerate
the SPM integration first: `cd example && flutter build ios --config-only`
(and `flutter build macos --config-only`).
