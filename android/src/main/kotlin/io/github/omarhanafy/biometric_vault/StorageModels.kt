package io.github.omarhanafy.biometric_vault

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import java.io.PrintWriter
import java.io.StringWriter
import kotlin.time.Duration

/** How an initialized cipher is going to be used. */
enum class CipherMode {
    Encrypt,
    Decrypt,
}

typealias ErrorCallback = (errorInfo: AuthenticationErrorInfo) -> Unit

/** Storage behavior configured once per storage file from the Dart `init` call. */
data class InitOptions(
    /**
     * When null, every access requires a fresh Class 3 (strong) biometric
     * authentication bound to the cipher through a `CryptoObject`
     * (auth-per-use key). When set, one successful authentication unlocks the
     * key for the given window (time-bound key) and the device credential is
     * accepted as a fallback on Android 11+.
     */
    val androidAuthenticationValidityDuration: Duration? = null,
    val authenticationRequired: Boolean = true,
    val androidBiometricOnly: Boolean = true,
)

/** Texts and behavior of the system authentication prompt, from the Dart side. */
data class AndroidPromptInfo(
    val title: String,
    val subtitle: String?,
    val description: String?,
    val negativeButton: String,
    val confirmationRequired: Boolean,
)

/**
 * Result of `canAuthenticate`. The wire format is the constant name and the
 * Dart side rejects unknown names, so constants must never be renamed and new
 * ones require a Dart-side mapping first.
 */
enum class CanAuthenticateResponse {
    Success,
    ErrorHwUnavailable,
    ErrorNoBiometricEnrolled,
    ErrorNoHardware,
    ErrorStatusUnknown,

    /** Neither a biometric nor a device credential is set up. */
    ErrorPasscodeNotSet,

    /** Biometrics are unusable until a security update is installed. */
    ErrorSecurityUpdateRequired,

    /** Maps to `CanAuthenticateResponse.unsupported` on the Dart side. */
    ErrorUnknown,
    ;

    companion object {
        fun fromBiometricManagerCode(code: Int): CanAuthenticateResponse = when (code) {
            BiometricManager.BIOMETRIC_SUCCESS -> Success
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> ErrorHwUnavailable
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> ErrorNoBiometricEnrolled
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> ErrorNoHardware
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED ->
                ErrorSecurityUpdateRequired
            BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED -> ErrorUnknown
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN -> ErrorStatusUnknown
            else -> ErrorStatusUnknown
        }
    }
}

/**
 * Error group reported to Dart as the `AuthError:<name>` error code.
 * The wire format is the constant name and every name has a dedicated
 * `AuthExceptionCode` value on the Dart side which matches on the exact
 * string, so constants must never be renamed and new ones require a
 * Dart-side mapping first.
 */
enum class AuthenticationError(private vararg val codes: Int) {
    Canceled(BiometricPrompt.ERROR_CANCELED),
    Timeout(BiometricPrompt.ERROR_TIMEOUT),
    UserCanceled(BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON),

    /** Too many failed attempts; locked out temporarily, retrying later may work. */
    LockedOut(BiometricPrompt.ERROR_LOCKOUT),

    /**
     * Locked out from too many [LockedOut] lockouts; biometrics stay disabled
     * until the user unlocks the device with their PIN, pattern or password.
     */
    LockedOutPermanently(BiometricPrompt.ERROR_LOCKOUT_PERMANENT),

    /** The sensor could not process the current attempt; the user may retry. */
    AuthenticationFailed(BiometricPrompt.ERROR_UNABLE_TO_PROCESS),

    /** No biometrics are enrolled on this device. */
    NoBiometricEnrolled(BiometricPrompt.ERROR_NO_BIOMETRICS),

    /** The device has no biometric hardware. */
    NoHardware(BiometricPrompt.ERROR_HW_NOT_PRESENT),

    /** The biometric hardware is currently unavailable; retrying later may work. */
    HardwareUnavailable(BiometricPrompt.ERROR_HW_UNAVAILABLE),

    /** A device credential was requested but no PIN, pattern or password is set up. */
    PasscodeNotSet(BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL),

    /** The biometric sensors are unusable until a security update is installed. */
    SecurityUpdateRequired(BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED),

    /** Fallback for ERROR_NO_SPACE, ERROR_VENDOR and any unmapped code. */
    Unknown(-1),

    /** The flow could not be started at all, e.g. without a FragmentActivity. */
    FailedToStart(-2),
    ;

    companion object {
        fun forCode(code: Int) = entries.firstOrNull { it.codes.contains(code) } ?: Unknown
    }
}

data class AuthenticationErrorInfo(
    val error: AuthenticationError,
    val message: CharSequence,
    val errorDetails: String? = null,
) {
    constructor(error: AuthenticationError, message: CharSequence, cause: Throwable) :
        this(error, message, cause.toCompleteString())
}

/** Errors with a well known error code that the Dart side can act upon. */
class MethodCallException(
    val errorCode: String,
    val errorMessage: String?,
    val errorDetails: Any? = null,
) : Exception(errorMessage ?: errorCode)

open class StorageException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** A stored payload exists but cannot be decrypted or parsed safely. */
class CorruptedStorageDataException(message: String, cause: Throwable? = null) :
    StorageException(message, cause)

/** The Android Keystore entry backing a storage file is permanently unusable. */
class InvalidatedStorageKeyException(message: String, cause: Throwable? = null) :
    StorageException(message, cause)

fun Throwable.toCompleteString(): String {
    val out = StringWriter()
    printStackTrace(PrintWriter(out))
    return "$this\n$out"
}
