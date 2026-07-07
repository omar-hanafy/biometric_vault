import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The device's ability to authenticate the user, as reported by
/// [BiometricVault.canAuthenticate].
///
/// As long as the response is not [unsupported] the secure storage itself is
/// usable; set [StorageFileInitOptions.authenticationRequired] to `false` to
/// store values without any authentication gate.
enum CanAuthenticateResponse {
  /// The user can authenticate right now with the requested authenticators.
  success,

  /// Biometric hardware exists but is currently unavailable.
  ///
  /// Examples: the sensor is busy or temporarily disabled, or on macOS the
  /// Touch ID equipped keyboard is disconnected. Trying again later may
  /// succeed.
  errorHwUnavailable,

  /// Biometric hardware is available but the user has not enrolled any
  /// biometry (no fingerprint, face, or iris registered).
  ///
  /// Direct the user to system settings to enroll, or fall back to
  /// non-biometric storage ([StorageFileInitOptions.authenticationRequired]
  /// set to `false`).
  errorNoBiometricEnrolled,

  /// The device has no biometric hardware, or on macOS no built-in or paired
  /// Touch ID is present.
  errorNoHardware,

  /// Authentication requires a device credential, but no passcode, PIN,
  /// pattern, or password is set up on the device.
  ///
  /// Reported on iOS and macOS when the passcode is disabled, and on Android
  /// when device-credential fallback was requested
  /// ([StorageFileInitOptions.androidBiometricOnly] set to `false`) while
  /// neither biometrics nor a credential are enrolled.
  errorPasscodeNotSet,

  /// Biometry is enrolled but locked after too many failed attempts.
  ///
  /// Reported on iOS and macOS. The lock clears after the user successfully
  /// authenticates with the device passcode (for example by locking and
  /// unlocking the device, or through any passcode-allowing prompt).
  /// Android cannot report lockout from a capability check; there it only
  /// surfaces when an actual prompt fails with
  /// [AuthExceptionCode.lockedOut] or
  /// [AuthExceptionCode.lockedOutPermanently].
  errorLockedOut,

  /// The biometric sensor is unusable until the device installs a security
  /// update. Reported on Android only.
  errorSecurityUpdateRequired,

  /// Android could not determine the biometric status; authentication may
  /// still succeed when actually attempted.
  ///
  /// See BIOMETRIC_STATUS_UNKNOWN in the androidx BiometricManager
  /// documentation. Treat it as "try and handle failure" rather than as an
  /// error.
  statusUnknown,

  /// This platform or embedder cannot authenticate at all.
  ///
  /// Returned on Windows, on the web, and for unknown platforms. The storage
  /// backends on those platforms are NOT protected by user authentication;
  /// see the package README for what each platform provides instead.
  unsupported,
}

const _canAuthenticateMapping = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorPasscodeNotSet': CanAuthenticateResponse.errorPasscodeNotSet,
  'ErrorLockedOut': CanAuthenticateResponse.errorLockedOut,
  'ErrorSecurityUpdateRequired':
      CanAuthenticateResponse.errorSecurityUpdateRequired,
  'ErrorStatusUnknown': CanAuthenticateResponse.statusUnknown,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
};

/// The biometry modality a device offers, as reported by
/// [BiometricVault.biometryType].
///
/// Use this to label authentication UI accurately ("Sign in with Face ID"
/// instead of a generic "Use biometrics"). The value describes the
/// **hardware capability**, not whether the user has enrolled: combine it
/// with [BiometricVault.canAuthenticate] before offering biometric UI.
enum BiometryType {
  /// The device has no biometric hardware, or the platform (Windows, web,
  /// Linux) cannot report one.
  none,

  /// Apple Face ID (iOS and macOS).
  faceId,

  /// Apple Touch ID (iOS and macOS).
  touchId,

  /// Apple Optic ID (visionOS-class devices; reported on iOS 17+ SDKs).
  opticId,

  /// A fingerprint sensor (Android).
  fingerprint,

  /// Face recognition hardware (Android).
  face,

  /// An iris scanner (Android).
  iris,

  /// The device declares more than one biometric modality (Android); the
  /// system prompt decides which one is used.
  multiple,

  /// Biometric hardware exists but the platform does not say which kind.
  /// Also returned for wire values this package version does not know yet.
  unknown,
}

const _biometryTypeMapping = {
  'None': BiometryType.none,
  'FaceId': BiometryType.faceId,
  'TouchId': BiometryType.touchId,
  'OpticId': BiometryType.opticId,
  'Fingerprint': BiometryType.fingerprint,
  'Face': BiometryType.face,
  'Iris': BiometryType.iris,
  'Multiple': BiometryType.multiple,
  'Unknown': BiometryType.unknown,
};

/// The reason an authentication-gated operation failed, carried by
/// [AuthException.code].
///
/// Every value the native platforms can produce has a dedicated code, so an
/// exhaustive `switch` over this enum handles all authentication outcomes.
enum AuthExceptionCode {
  /// The user dismissed the prompt on purpose, for example by tapping the
  /// negative button or pressing back on Android, or by canceling the
  /// Face ID / Touch ID sheet on iOS and macOS.
  ///
  /// Usually needs no error UI; the user knows they canceled.
  userCanceled,

  /// The system canceled the prompt without an explicit user decision.
  ///
  /// Examples: the app moved to the background, another window took focus,
  /// or the platform could not show authentication UI. Retrying when the app
  /// is active again is usually appropriate.
  canceled,

  /// The prompt timed out waiting for the user. Reported on Android only.
  timeout,

  /// Biometry is temporarily locked after too many failed attempts.
  ///
  /// On Android the lock clears by itself after roughly 30 seconds. On iOS
  /// and macOS it clears once the user authenticates with the device
  /// passcode. Offer to retry later, or authenticate with
  /// [StorageFileInitOptions.darwinBiometricOnly] /
  /// [StorageFileInitOptions.androidBiometricOnly] set to `false` so the
  /// system can offer the device credential.
  lockedOut,

  /// Biometry is locked until the user unlocks with a device credential.
  ///
  /// Reported on Android after repeated lockouts. The biometric prompt
  /// cannot succeed until the user authenticates with PIN, pattern, or
  /// password (for example through the device lock screen).
  lockedOutPermanently,

  /// The user was not recognized and authentication genuinely failed.
  ///
  /// On iOS and macOS this is the keychain reporting failed authentication.
  /// On Android it maps from a sensor that could not process the input.
  authenticationFailed,

  /// No biometry is enrolled anymore.
  ///
  /// Happens when enrollment was removed between the capability check and
  /// the prompt. Reported on Android; re-check with
  /// [BiometricVault.canAuthenticate] and guide the user to re-enroll.
  noBiometricEnrolled,

  /// The device has no biometric hardware. Reported on Android when a prompt
  /// was attempted anyway.
  noHardware,

  /// Biometric hardware is present but currently unavailable. Reported on
  /// Android; trying again later may succeed.
  hardwareUnavailable,

  /// Device-credential fallback was requested but no PIN, pattern, or
  /// password is set up. Reported on Android.
  passcodeNotSet,

  /// The sensor is disabled until a security update is installed. Reported
  /// on Android.
  securityUpdateRequired,

  /// The authentication flow could not be started at all.
  ///
  /// On Android this almost always means the activity is not a
  /// `FlutterFragmentActivity`, which the biometric prompt requires; see the
  /// package README's setup section.
  failedToStart,

  /// Reading from the Linux secret service was denied by an AppArmor
  /// profile, typically inside a snap.
  /// [BiometricVault.linuxCheckAppArmorError] probes for this state.
  linuxAppArmorDenied,

  /// The platform reported an error this package has no dedicated code for.
  /// The [AuthException.message] carries the platform's description.
  unknown,
}

const _authErrorCodeMapping = {
  'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
  'AuthError:Canceled': AuthExceptionCode.canceled,
  'AuthError:Timeout': AuthExceptionCode.timeout,
  'AuthError:LockedOut': AuthExceptionCode.lockedOut,
  'AuthError:LockedOutPermanently': AuthExceptionCode.lockedOutPermanently,
  'AuthError:AuthenticationFailed': AuthExceptionCode.authenticationFailed,
  'AuthError:NoBiometricEnrolled': AuthExceptionCode.noBiometricEnrolled,
  'AuthError:NoHardware': AuthExceptionCode.noHardware,
  'AuthError:HardwareUnavailable': AuthExceptionCode.hardwareUnavailable,
  'AuthError:PasscodeNotSet': AuthExceptionCode.passcodeNotSet,
  'AuthError:SecurityUpdateRequired': AuthExceptionCode.securityUpdateRequired,
  'AuthError:FailedToStart': AuthExceptionCode.failedToStart,
  'AuthError:Unknown': AuthExceptionCode.unknown,
};

/// Why stored data became unusable, carried by
/// [StorageInvalidatedException.reason].
enum StorageInvalidatedReason {
  /// The platform invalidated the encryption key backing the storage.
  ///
  /// On Android this happens when the user changes biometric enrollment
  /// (adds or removes a fingerprint or face); the Android Keystore then
  /// permanently invalidates keys that require user authentication.
  keyInvalidated,

  /// The stored payload exists but cannot be decrypted or parsed safely,
  /// for example after partial disk corruption.
  corruptedData,
}

/// The common base type for every failure this plugin reports.
///
/// The hierarchy is sealed, so a `switch` over an instance is exhaustive:
///
/// ```dart
/// try {
///   await file.read();
/// } on BiometricVaultException catch (e) {
///   switch (e) {
///     case AuthException(:final code):
///       // The user could not or did not authenticate; inspect [code].
///     case StorageInvalidatedException():
///       // The stored value is gone for good; re-provision it.
///     case BiometricVaultPluginException():
///       // Unexpected platform failure; report it.
///   }
/// }
/// ```
sealed class BiometricVaultException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const BiometricVaultException(this.message);

  /// A human-readable description of the failure, suitable for logs.
  ///
  /// Not localized; do not show it to end users directly.
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// The user could not be authenticated for a storage operation.
///
/// Thrown by [BiometricVaultFile.read], [BiometricVaultFile.write] and
/// [BiometricVaultFile.delete] when authentication fails, is canceled, or
/// cannot be performed. [code] states the exact reason; the stored data
/// itself is unaffected and the operation can be retried.
final class AuthException extends BiometricVaultException {
  /// Creates an authentication failure with its typed [code].
  const AuthException(this.code, String message) : super(message);

  /// The typed reason for this failure; see [AuthExceptionCode] for the
  /// recommended reaction to each value.
  final AuthExceptionCode code;

  @override
  String toString() => 'AuthException($code, $message)';
}

/// The stored value exists but is permanently unusable.
///
/// Unlike [AuthException] this is NOT retryable: the underlying data or its
/// encryption key is gone. Delete the storage (or simply write a new value)
/// and re-provision the secret, typically by asking the user to sign in
/// again.
final class StorageInvalidatedException extends BiometricVaultException {
  /// Creates an invalidation failure with its typed [reason].
  const StorageInvalidatedException(this.reason, String message)
    : super(message);

  /// What invalidated the storage; see [StorageInvalidatedReason].
  final StorageInvalidatedReason reason;

  @override
  String toString() => 'StorageInvalidatedException($reason, $message)';
}

/// An unexpected platform-side failure that is neither an authentication
/// outcome nor data invalidation.
///
/// [code] is the raw platform error code (for example `SecurityError` or
/// `NoSuchStorage`) and [details] carries any extra diagnostic payload the
/// platform attached. Seeing this exception usually indicates a bug or an
/// integration problem worth reporting.
final class BiometricVaultPluginException extends BiometricVaultException {
  /// Creates a wrapped platform exception preserving [code] and [details].
  const BiometricVaultPluginException(this.code, String message, this.details)
    : super(message);

  /// The raw error code reported by the platform implementation.
  final String code;

  /// Additional diagnostic information from the platform, often a native
  /// stack trace. May be `null`.
  final Object? details;

  @override
  String toString() => 'BiometricVaultPluginException($code, $message)';
}

/// Configuration for a storage file, applied once when the storage is
/// created by [BiometricVault.getStorage].
///
/// The options are persisted natively per storage name; passing different
/// options for an already created storage has no effect until the storage is
/// deleted and recreated.
class StorageFileInitOptions {
  /// Creates storage options; every parameter has a secure-by-default value.
  const StorageFileInitOptions({
    this.androidAuthenticationValidityDuration,
    this.darwinTouchIDAuthenticationAllowableReuseDuration,
    this.darwinTouchIDAuthenticationForceReuseContextDuration,
    this.authenticationRequired = true,
    this.androidBiometricOnly = true,
    this.darwinBiometricOnly = true,
    this.silentWrites = false,
  });

  /// How long one successful authentication stays valid on Android.
  ///
  /// When `null` (the default), every access requires a fresh Class 3
  /// (strong) biometric authentication cryptographically bound to the
  /// operation. When set, one authentication unlocks the key for the given
  /// window and the device credential is accepted as a fallback on
  /// Android 11 and newer.
  ///
  /// Must be set when [androidBiometricOnly] is `false`;
  /// [BiometricVault.getStorage] rejects that combination on Android.
  ///
  /// See `setUserAuthenticationParameters` in the Android KeyGenParameterSpec
  /// documentation.
  final Duration? androidAuthenticationValidityDuration;

  /// The grace period after a device unlock with Touch ID during which
  /// keychain access does not prompt again, on iOS and macOS.
  ///
  /// Values above the system maximum of 5 minutes are clamped natively.
  /// This mirrors `LAContext.touchIDAuthenticationAllowableReuseDuration`
  /// and applies specifically to device unlock, not to previous keychain
  /// prompts; to avoid re-prompting after a successful keychain operation
  /// use [darwinTouchIDAuthenticationForceReuseContextDuration] instead.
  final Duration? darwinTouchIDAuthenticationAllowableReuseDuration;

  /// How long the plugin reuses one authenticated `LAContext` for further
  /// keychain operations on iOS and macOS.
  ///
  /// While the context is reused, reads and writes within this window do not
  /// prompt again, similar to [androidAuthenticationValidityDuration] on
  /// Android. Independent of
  /// [darwinTouchIDAuthenticationAllowableReuseDuration]; setting one does
  /// not imply the other.
  final Duration? darwinTouchIDAuthenticationForceReuseContextDuration;

  /// Whether accessing this storage requires the user to authenticate.
  ///
  /// When `false` NO authentication gate exists: values are still stored
  /// through the platform keystore or keychain, but any app code can read
  /// them without a prompt.
  final bool authenticationRequired;

  /// Whether Android may only use biometrics, excluding PIN, pattern, and
  /// password fallback.
  ///
  /// When `false`, the device credential is offered as a fallback, which
  /// requires Android 11 or newer (older versions ignore the fallback) and
  /// requires [androidAuthenticationValidityDuration] to be set because
  /// auth-per-use keys only support biometric authentication.
  final bool androidBiometricOnly;

  /// Whether iOS and macOS may only use biometry that is currently enrolled
  /// (`.biometryCurrentSet`), excluding the device passcode.
  ///
  /// When `false`, `.userPresence` is used instead and the system offers the
  /// passcode as a fallback. Note that with `.biometryCurrentSet` the stored
  /// item becomes unreadable if the user re-enrolls biometry.
  final bool darwinBiometricOnly;

  /// Whether [BiometricVaultFile.write] completes without any
  /// authentication prompt while [BiometricVaultFile.read] stays gated.
  ///
  /// Designed for frequently rotated secrets (such as refresh tokens):
  /// the app can persist a new value at any time - even from a background
  /// refresh - and the user only authenticates when the value is read back.
  ///
  /// How it works: on Android the payload is encrypted with a fresh
  /// AES-256-GCM key that is wrapped by an RSA public key; only the
  /// RSA private key (which unwraps during [BiometricVaultFile.read]) is
  /// gated by user authentication. On iOS and macOS writes replace the
  /// keychain item (delete + add), which never evaluates the item's access
  /// control; reads still do.
  ///
  /// After a biometric re-enrollment the read key is invalidated as usual
  /// ([StorageInvalidatedException]) but writes keep succeeding, so an app
  /// can silently re-provision the secret on its next sign-in.
  ///
  /// Has no effect when [authenticationRequired] is `false`.
  final bool silentWrites;

  /// The wire representation sent to the platform implementations.
  ///
  /// The key names are a fixed part of the plugin's internal protocol.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'androidAuthenticationValidityDurationSeconds':
        androidAuthenticationValidityDuration?.inSeconds,
    'darwinTouchIDAuthenticationAllowableReuseDurationSeconds':
        darwinTouchIDAuthenticationAllowableReuseDuration?.inSeconds,
    'darwinTouchIDAuthenticationForceReuseContextDurationSeconds':
        darwinTouchIDAuthenticationForceReuseContextDuration?.inSeconds,
    'authenticationRequired': authenticationRequired,
    'androidBiometricOnly': androidBiometricOnly,
    'darwinBiometricOnly': darwinBiometricOnly,
    'silentWrites': silentWrites,
  };
}

/// Texts and behavior of the Android system authentication prompt.
///
/// Android renders one prompt per protected operation; these values fill the
/// system-provided sheet. See [PromptInfo] for how the per-platform
/// configurations are combined.
class AndroidPromptInfo {
  /// Creates the Android prompt configuration.
  const AndroidPromptInfo({
    this.title = 'Authenticate to unlock data',
    this.subtitle,
    this.description,
    this.negativeButton = 'Cancel',
    this.confirmationRequired = true,
  });

  /// The headline of the prompt sheet.
  final String title;

  /// An optional second line below [title].
  final String? subtitle;

  /// Optional longer text explaining why authentication is needed.
  final String? description;

  /// The label of the cancel button.
  ///
  /// Only shown when [StorageFileInitOptions.androidBiometricOnly] is `true`;
  /// with device-credential fallback Android replaces it with the fallback
  /// entry point.
  final String negativeButton;

  /// Whether passive biometrics (like face unlock) require an explicit
  /// confirmation tap after recognition.
  final bool confirmationRequired;

  /// The configuration used when none is provided explicitly.
  static const defaultValues = AndroidPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'negativeButton': negativeButton,
    'confirmationRequired': confirmationRequired,
  };
}

/// Prompt messages shown by iOS and macOS when the keychain asks the user to
/// authenticate.
///
/// Apple's UI only exposes a single reason string per operation; [saveTitle]
/// is used while writing and [accessTitle] while reading or deleting.
class DarwinPromptInfo {
  /// Creates the iOS/macOS prompt configuration.
  const DarwinPromptInfo({
    this.saveTitle = 'Unlock to save data',
    this.accessTitle = 'Unlock to access data',
  });

  /// The reason shown while writing a value.
  final String saveTitle;

  /// The reason shown while reading or deleting a value.
  final String accessTitle;

  /// The configuration used when none is provided explicitly.
  static const defaultValues = DarwinPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
    'saveTitle': saveTitle,
    'accessTitle': accessTitle,
  };
}

/// The per-platform prompt configurations for one storage operation.
///
/// Only the configuration matching the current platform is sent to the
/// native side; the others are ignored, so one [PromptInfo] can safely be
/// shared across a cross-platform code base.
class PromptInfo {
  /// Creates a bundle of per-platform prompt configurations.
  const PromptInfo({
    this.androidPromptInfo = AndroidPromptInfo.defaultValues,
    this.iosPromptInfo = DarwinPromptInfo.defaultValues,
    this.macOsPromptInfo = DarwinPromptInfo.defaultValues,
  });

  /// The configuration used when none is provided explicitly.
  static const defaultValues = PromptInfo();

  /// Prompt texts used on Android.
  final AndroidPromptInfo androidPromptInfo;

  /// Prompt texts used on iOS.
  final DarwinPromptInfo iosPromptInfo;

  /// Prompt texts used on macOS.
  final DarwinPromptInfo macOsPromptInfo;
}

/// The entry point for biometric/secure storage.
///
/// `BiometricVault()` returns the platform singleton. Typical usage:
///
/// ```dart
/// final support = await BiometricVault().canAuthenticate();
/// if (support == CanAuthenticateResponse.success) {
///   final storage = await BiometricVault().getStorage('my_token');
///   await storage.write('secret');
///   final value = await storage.read();
/// }
/// ```
///
/// See [CanAuthenticateResponse] for interpreting capability results and
/// [BiometricVaultException] for the failure contract of all operations.
abstract class BiometricVault extends PlatformInterface {
  /// The active platform implementation.
  factory BiometricVault() => _instance;

  /// Constructor for platform implementations to call as `super.create()`.
  BiometricVault.create() : super(token: _token);

  static BiometricVault _instance = MethodChannelBiometricVault();

  /// Registers a platform-specific implementation, replacing the default
  /// method-channel one. Called by the Windows and web backends.
  static set instance(BiometricVault instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  static const Object _token = Object();

  /// Whether this device can authenticate the user right now, and if not,
  /// why.
  ///
  /// Pass [options] when the storage will be created with non-default
  /// authenticator settings (for example
  /// [StorageFileInitOptions.androidBiometricOnly] set to `false`), so the
  /// check matches the authenticators that will actually be used.
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  });

  /// Whether reading from the Linux secret service is blocked by an
  /// AppArmor policy, as happens inside snaps without the right plugs.
  ///
  /// Performs a real read against a throwaway, non-authenticated storage
  /// entry and returns `true` when the denial signature is detected.
  /// Always returns `false` on other platforms.
  Future<bool> linuxCheckAppArmorError();

  /// The biometry modality this device offers, for accurate UI labels.
  ///
  /// Reports the hardware capability (Face ID vs Touch ID vs fingerprint),
  /// NOT whether the user has enrolled or can authenticate right now; check
  /// [canAuthenticate] for that. Platforms without biometric support
  /// (Windows, web, Linux) report [BiometryType.none].
  Future<BiometryType> biometryType() async => BiometryType.none;

  /// Authenticates the user without touching any storage.
  ///
  /// Use this for gates that only need proof of presence, such as an
  /// app-lock screen shown when the app returns from the background. It
  /// does NOT unlock any [BiometricVaultFile]; reads still authenticate on
  /// their own terms.
  ///
  /// Completes normally when the user authenticated. Throws an
  /// [AuthException] when authentication fails, is canceled, or cannot
  /// start; the [AuthExceptionCode] states the exact reason.
  ///
  /// With [biometricOnly] set to `true` only biometrics are accepted; the
  /// default also offers the device credential (passcode, PIN, pattern) as
  /// a fallback, which is usually right for privacy gates.
  ///
  /// On platforms without user authentication (Windows, web, Linux) this
  /// throws a [BiometricVaultPluginException] with code `Unsupported`;
  /// call [canAuthenticate] first to avoid that.
  Future<void> authenticate({
    PromptInfo promptInfo = PromptInfo.defaultValues,
    bool biometricOnly = false,
  }) async => throw const BiometricVaultPluginException(
    'Unsupported',
    'User authentication is not supported on this platform. '
        'Check canAuthenticate() before calling authenticate().',
    null,
  );

  /// Opens (creating on first use) the storage file named [name].
  ///
  /// Each name is a fully separate store with its own encryption key and
  /// its own [options]; the options are applied when the store is first
  /// created and ignored afterwards. The returned [BiometricVaultFile]
  /// uses [promptInfo] for operations that do not pass their own.
  ///
  /// The [name] must be a plain identifier: not empty and without `/` or
  /// `\` characters; anything else throws an [ArgumentError] before any
  /// platform code runs. On Android, combining
  /// `androidBiometricOnly: false` with a `null`
  /// [StorageFileInitOptions.androidAuthenticationValidityDuration] also
  /// throws an [ArgumentError] because the platform cannot express it.
  ///
  /// If [forceInit] is `true` and the storage was already initialized in
  /// this process, throws a [BiometricVaultPluginException] with code
  /// `AlreadyInitialized`.
  Future<BiometricVaultFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  });

  /// Reads the current value of the store named [name].
  ///
  /// Prefer [BiometricVaultFile.read]; this exists for implementations.
  @protected
  Future<String?> read(String name, PromptInfo promptInfo);

  /// Deletes the store named [name].
  ///
  /// Prefer [BiometricVaultFile.delete]; this exists for implementations.
  @protected
  Future<bool?> delete(String name, PromptInfo promptInfo);

  /// Writes [content] into the store named [name].
  ///
  /// Prefer [BiometricVaultFile.write]; this exists for implementations.
  @protected
  Future<void> write(String name, String content, PromptInfo promptInfo);
}

/// The method-channel implementation of [BiometricVault], used on
/// Android, iOS, macOS, and Linux.
class MethodChannelBiometricVault extends BiometricVault {
  /// Creates the method-channel backed implementation.
  MethodChannelBiometricVault() : super.create();

  static const MethodChannel _channel = MethodChannel('biometric_vault');

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async {
    // On the web the registered web implementation replaces this class;
    // this guard only protects exotic embedders that skip registration.
    if (kIsWeb) {
      return CanAuthenticateResponse.unsupported;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        final response = await _channel.invokeMethod<String>(
          'canAuthenticate',
          {'options': (options ?? const StorageFileInitOptions()).toJson()},
        );
        final ret = _canAuthenticateMapping[response];
        if (ret == null) {
          throw StateError(
            'Invalid response from native platform. '
            '{$response}',
          );
        }
        return ret;
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return CanAuthenticateResponse.unsupported;
    }
  }

  @override
  Future<BiometryType> biometryType() async {
    if (kIsWeb) {
      return BiometryType.none;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        final response = await _transformErrors(
          _channel.invokeMethod<String>('biometryType'),
        );
        // Lenient by design: a newer native side may report a modality this
        // Dart version does not know yet; that is not an error condition.
        return _biometryTypeMapping[response] ?? BiometryType.unknown;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return BiometryType.none;
    }
  }

  @override
  Future<void> authenticate({
    PromptInfo promptInfo = PromptInfo.defaultValues,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) {
      return super.authenticate(
        promptInfo: promptInfo,
        biometricOnly: biometricOnly,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        await _transformErrors(
          _channel.invokeMethod<void>('authenticate', <String, dynamic>{
            'biometricOnly': biometricOnly,
            ..._promptInfoForCurrentPlatform(promptInfo),
          }),
        );
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        // The libsecret, Windows, and fuchsia backends have no user
        // authentication; the base class throws the documented exception.
        await super.authenticate(
          promptInfo: promptInfo,
          biometricOnly: biometricOnly,
        );
    }
  }

  @override
  Future<bool> linuxCheckAppArmorError() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
      return false;
    }
    final tmpStorage = await getStorage(
      'appArmorCheck',
      options: const StorageFileInitOptions(authenticationRequired: false),
    );
    try {
      await tmpStorage.read();
      return false;
    } on AuthException catch (e) {
      if (e.code == AuthExceptionCode.linuxAppArmorDenied) {
        return true;
      }
      rethrow;
    }
  }

  @override
  Future<BiometricVaultFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    _validateName(name);
    final resolvedOptions = options ?? const StorageFileInitOptions();
    _validateOptionsForPlatform(resolvedOptions);
    await _transformErrors(
      _channel.invokeMethod<bool>('init', {
        'name': name,
        'options': resolvedOptions.toJson(),
        'forceInit': forceInit,
      }),
    );
    return BiometricVaultFile(this, name, promptInfo);
  }

  /// Rejects names that would escape the per-store namespace.
  ///
  /// Android additionally validates this natively; checking here gives every
  /// platform the same fail-fast behavior before any IO happens.
  static void _validateName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Storage name must not be empty.',
      );
    }
    if (name.contains('/') || name.contains(r'\')) {
      throw ArgumentError.value(
        name,
        'name',
        'Storage name must be a plain name without path separators.',
      );
    }
  }

  /// Rejects option combinations the current platform cannot express, so
  /// misconfiguration fails at development time instead of surfacing as a
  /// native error during the first read.
  static void _validateOptionsForPlatform(StorageFileInitOptions options) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (!options.androidBiometricOnly &&
          options.androidAuthenticationValidityDuration == null) {
        throw ArgumentError(
          'androidBiometricOnly: false requires '
          'androidAuthenticationValidityDuration to be set, because '
          'auth-per-use keys only support biometric authentication on '
          'Android.',
        );
      }
    }
  }

  @override
  Future<String?> read(String name, PromptInfo promptInfo) => _transformErrors(
    _channel.invokeMethod<String>('read', <String, dynamic>{
      'name': name,
      ..._promptInfoForCurrentPlatform(promptInfo),
    }),
  );

  @override
  Future<bool?> delete(String name, PromptInfo promptInfo) => _transformErrors(
    _channel.invokeMethod<bool>('delete', <String, dynamic>{
      'name': name,
      ..._promptInfoForCurrentPlatform(promptInfo),
    }),
  );

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) =>
      _transformErrors(
        _channel.invokeMethod('write', <String, dynamic>{
          'name': name,
          'content': content,
          ..._promptInfoForCurrentPlatform(promptInfo),
        }),
      );

  /// The prompt payload for the current platform only, so Android texts are
  /// never sent to iOS and vice versa.
  Map<String, dynamic> _promptInfoForCurrentPlatform(PromptInfo promptInfo) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return <String, dynamic>{
          'androidPromptInfo': promptInfo.androidPromptInfo._toJson(),
        };
      case TargetPlatform.iOS:
        return <String, dynamic>{
          'iosPromptInfo': promptInfo.iosPromptInfo._toJson(),
        };
      case TargetPlatform.macOS:
        // iOS and macOS share one native implementation, hence one wire key.
        return <String, dynamic>{
          'iosPromptInfo': promptInfo.macOsPromptInfo._toJson(),
        };
      case TargetPlatform.linux:
        return <String, dynamic>{};
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        // Windows registers a Dart-only implementation; reaching this line
        // means the platform setup is broken.
        throw StateError(
          'Unsupported platform $defaultTargetPlatform for method channel '
          'operations.',
        );
    }
  }

  /// Converts platform-channel failures into the sealed
  /// [BiometricVaultException] hierarchy; every other error type passes
  /// through untouched.
  Future<T> _transformErrors<T>(Future<T> future) =>
      future.catchError((Object error, StackTrace stackTrace) {
        if (error is PlatformException) {
          return Future<T>.error(_mapPlatformException(error), stackTrace);
        }
        return Future<T>.error(error, stackTrace);
      });

  static BiometricVaultException _mapPlatformException(
    PlatformException error,
  ) {
    final message = error.message ?? error.code;
    if (error.code.startsWith('AuthError:')) {
      return AuthException(
        _authErrorCodeMapping[error.code] ?? AuthExceptionCode.unknown,
        message,
      );
    }
    if (error.code == 'StorageError:KeyInvalidated') {
      return StorageInvalidatedException(
        StorageInvalidatedReason.keyInvalidated,
        message,
      );
    }
    if (error.code == 'StorageError:CorruptedData') {
      return StorageInvalidatedException(
        StorageInvalidatedReason.corruptedData,
        message,
      );
    }
    final details = error.details;
    if (details is Map) {
      final detailMessage = details['message'];
      if (detailMessage is String &&
          (detailMessage.contains('org.freedesktop.DBus.Error.AccessDenied') ||
              detailMessage.contains('AppArmor'))) {
        return AuthException(AuthExceptionCode.linuxAppArmorDenied, message);
      }
    }
    return BiometricVaultPluginException(error.code, message, error.details);
  }
}

/// One named, isolated secure store obtained from
/// [BiometricVault.getStorage].
///
/// All operations may show a platform authentication prompt (depending on
/// the store's [StorageFileInitOptions]) and throw subtypes of
/// [BiometricVaultException] on failure.
class BiometricVaultFile {
  /// Binds the store [name] to [_plugin] with its [defaultPromptInfo].
  BiometricVaultFile(this._plugin, this.name, this.defaultPromptInfo);

  final BiometricVault _plugin;

  /// The unique name of this store, as passed to
  /// [BiometricVault.getStorage].
  final String name;

  /// The prompt configuration used when an operation does not pass its own.
  final PromptInfo defaultPromptInfo;

  /// The stored value, or `null` when nothing was stored yet (or the value
  /// was deleted).
  ///
  /// Throws an [AuthException] when the user cannot be authenticated and a
  /// [StorageInvalidatedException] when the value is permanently
  /// unrecoverable.
  Future<String?> read({PromptInfo? promptInfo}) =>
      _plugin.read(name, promptInfo ?? defaultPromptInfo);

  /// Overwrites the stored value with [content].
  ///
  /// Throws an [AuthException] when the user cannot be authenticated; in
  /// that case the previous value stays intact.
  Future<void> write(String content, {PromptInfo? promptInfo}) =>
      _plugin.write(name, content, promptInfo ?? defaultPromptInfo);

  /// Deletes the stored value.
  ///
  /// Completes normally when nothing was stored. After deleting, [read]
  /// returns `null`.
  Future<void> delete({PromptInfo? promptInfo}) =>
      _plugin.delete(name, promptInfo ?? defaultPromptInfo);
}
