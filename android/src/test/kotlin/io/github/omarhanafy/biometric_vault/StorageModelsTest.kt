package io.github.omarhanafy.biometric_vault

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Guards the frozen v6 wire contract: the enum constant name IS the wire
 * string reported to Dart (as `AuthError:<name>` or the `canAuthenticate`
 * result) and the Dart side matches on these exact strings, so neither the
 * names nor the code mappings may ever change silently.
 */
class StorageModelsTest {

    // AuthenticationError.forCode: BiometricPrompt error codes to wire names.

    @Test
    fun `forCode maps ERROR_CANCELED to Canceled`() {
        assertEquals(
            AuthenticationError.Canceled,
            AuthenticationError.forCode(BiometricPrompt.ERROR_CANCELED),
        )
    }

    @Test
    fun `forCode maps ERROR_TIMEOUT to Timeout`() {
        assertEquals(
            AuthenticationError.Timeout,
            AuthenticationError.forCode(BiometricPrompt.ERROR_TIMEOUT),
        )
    }

    @Test
    fun `forCode maps ERROR_USER_CANCELED and ERROR_NEGATIVE_BUTTON to UserCanceled`() {
        assertEquals(
            AuthenticationError.UserCanceled,
            AuthenticationError.forCode(BiometricPrompt.ERROR_USER_CANCELED),
        )
        assertEquals(
            AuthenticationError.UserCanceled,
            AuthenticationError.forCode(BiometricPrompt.ERROR_NEGATIVE_BUTTON),
        )
    }

    @Test
    fun `forCode maps ERROR_LOCKOUT to LockedOut`() {
        assertEquals(
            AuthenticationError.LockedOut,
            AuthenticationError.forCode(BiometricPrompt.ERROR_LOCKOUT),
        )
    }

    @Test
    fun `forCode maps ERROR_LOCKOUT_PERMANENT to LockedOutPermanently`() {
        assertEquals(
            AuthenticationError.LockedOutPermanently,
            AuthenticationError.forCode(BiometricPrompt.ERROR_LOCKOUT_PERMANENT),
        )
    }

    @Test
    fun `forCode maps ERROR_UNABLE_TO_PROCESS to AuthenticationFailed`() {
        assertEquals(
            AuthenticationError.AuthenticationFailed,
            AuthenticationError.forCode(BiometricPrompt.ERROR_UNABLE_TO_PROCESS),
        )
    }

    @Test
    fun `forCode maps ERROR_NO_BIOMETRICS to NoBiometricEnrolled`() {
        assertEquals(
            AuthenticationError.NoBiometricEnrolled,
            AuthenticationError.forCode(BiometricPrompt.ERROR_NO_BIOMETRICS),
        )
    }

    @Test
    fun `forCode maps ERROR_HW_NOT_PRESENT to NoHardware`() {
        assertEquals(
            AuthenticationError.NoHardware,
            AuthenticationError.forCode(BiometricPrompt.ERROR_HW_NOT_PRESENT),
        )
    }

    @Test
    fun `forCode maps ERROR_HW_UNAVAILABLE to HardwareUnavailable`() {
        assertEquals(
            AuthenticationError.HardwareUnavailable,
            AuthenticationError.forCode(BiometricPrompt.ERROR_HW_UNAVAILABLE),
        )
    }

    @Test
    fun `forCode maps ERROR_NO_DEVICE_CREDENTIAL to PasscodeNotSet`() {
        assertEquals(
            AuthenticationError.PasscodeNotSet,
            AuthenticationError.forCode(BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL),
        )
    }

    @Test
    fun `forCode maps ERROR_SECURITY_UPDATE_REQUIRED to SecurityUpdateRequired`() {
        assertEquals(
            AuthenticationError.SecurityUpdateRequired,
            AuthenticationError.forCode(BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED),
        )
    }

    @Test
    fun `forCode maps ERROR_NO_SPACE, ERROR_VENDOR and unmapped codes to Unknown`() {
        assertEquals(
            AuthenticationError.Unknown,
            AuthenticationError.forCode(BiometricPrompt.ERROR_NO_SPACE),
        )
        assertEquals(
            AuthenticationError.Unknown,
            AuthenticationError.forCode(BiometricPrompt.ERROR_VENDOR),
        )
        assertEquals(
            AuthenticationError.Unknown,
            AuthenticationError.forCode(999),
        )
    }

    @Test
    fun `forCode maps every raw framework error code per the frozen wire contract`() {
        // Raw numeric values as delivered by the OS at runtime, pinned
        // independently of the androidx constants used above.
        val expected = mapOf(
            1 to AuthenticationError.HardwareUnavailable,
            2 to AuthenticationError.AuthenticationFailed,
            3 to AuthenticationError.Timeout,
            4 to AuthenticationError.Unknown,
            5 to AuthenticationError.Canceled,
            7 to AuthenticationError.LockedOut,
            8 to AuthenticationError.Unknown,
            9 to AuthenticationError.LockedOutPermanently,
            10 to AuthenticationError.UserCanceled,
            11 to AuthenticationError.NoBiometricEnrolled,
            12 to AuthenticationError.NoHardware,
            13 to AuthenticationError.UserCanceled,
            14 to AuthenticationError.PasscodeNotSet,
            15 to AuthenticationError.SecurityUpdateRequired,
        )
        expected.forEach { (code, error) ->
            assertEquals("forCode($code)", error, AuthenticationError.forCode(code))
        }
    }

    // CanAuthenticateResponse.fromBiometricManagerCode: BiometricManager codes
    // to wire names.

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_SUCCESS to Success`() {
        assertEquals(
            CanAuthenticateResponse.Success,
            CanAuthenticateResponse.fromBiometricManagerCode(BiometricManager.BIOMETRIC_SUCCESS),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_ERROR_HW_UNAVAILABLE to ErrorHwUnavailable`() {
        assertEquals(
            CanAuthenticateResponse.ErrorHwUnavailable,
            CanAuthenticateResponse.fromBiometricManagerCode(
                BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE,
            ),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_ERROR_NONE_ENROLLED to ErrorNoBiometricEnrolled`() {
        assertEquals(
            CanAuthenticateResponse.ErrorNoBiometricEnrolled,
            CanAuthenticateResponse.fromBiometricManagerCode(
                BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED,
            ),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_ERROR_NO_HARDWARE to ErrorNoHardware`() {
        assertEquals(
            CanAuthenticateResponse.ErrorNoHardware,
            CanAuthenticateResponse.fromBiometricManagerCode(
                BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE,
            ),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED to ErrorSecurityUpdateRequired`() {
        assertEquals(
            CanAuthenticateResponse.ErrorSecurityUpdateRequired,
            CanAuthenticateResponse.fromBiometricManagerCode(
                BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED,
            ),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_ERROR_UNSUPPORTED to ErrorUnknown`() {
        assertEquals(
            CanAuthenticateResponse.ErrorUnknown,
            CanAuthenticateResponse.fromBiometricManagerCode(
                BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED,
            ),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps BIOMETRIC_STATUS_UNKNOWN to ErrorStatusUnknown`() {
        assertEquals(
            CanAuthenticateResponse.ErrorStatusUnknown,
            CanAuthenticateResponse.fromBiometricManagerCode(
                BiometricManager.BIOMETRIC_STATUS_UNKNOWN,
            ),
        )
    }

    @Test
    fun `fromBiometricManagerCode maps unknown codes to ErrorStatusUnknown`() {
        assertEquals(
            CanAuthenticateResponse.ErrorStatusUnknown,
            CanAuthenticateResponse.fromBiometricManagerCode(12345),
        )
    }

    // Wire-name invariants: the Dart side matches on these exact strings.

    @Test
    fun `AuthenticationError constant names are the frozen wire strings`() {
        assertEquals("Canceled", AuthenticationError.Canceled.name)
        assertEquals("Timeout", AuthenticationError.Timeout.name)
        assertEquals("UserCanceled", AuthenticationError.UserCanceled.name)
        assertEquals("LockedOut", AuthenticationError.LockedOut.name)
        assertEquals("LockedOutPermanently", AuthenticationError.LockedOutPermanently.name)
        assertEquals("AuthenticationFailed", AuthenticationError.AuthenticationFailed.name)
        assertEquals("NoBiometricEnrolled", AuthenticationError.NoBiometricEnrolled.name)
        assertEquals("NoHardware", AuthenticationError.NoHardware.name)
        assertEquals("HardwareUnavailable", AuthenticationError.HardwareUnavailable.name)
        assertEquals("PasscodeNotSet", AuthenticationError.PasscodeNotSet.name)
        assertEquals("SecurityUpdateRequired", AuthenticationError.SecurityUpdateRequired.name)
        assertEquals("FailedToStart", AuthenticationError.FailedToStart.name)
        assertEquals("Unknown", AuthenticationError.Unknown.name)
    }

    @Test
    fun `CanAuthenticateResponse constant names are the frozen wire strings`() {
        assertEquals("Success", CanAuthenticateResponse.Success.name)
        assertEquals("ErrorHwUnavailable", CanAuthenticateResponse.ErrorHwUnavailable.name)
        assertEquals(
            "ErrorNoBiometricEnrolled",
            CanAuthenticateResponse.ErrorNoBiometricEnrolled.name,
        )
        assertEquals("ErrorNoHardware", CanAuthenticateResponse.ErrorNoHardware.name)
        assertEquals("ErrorStatusUnknown", CanAuthenticateResponse.ErrorStatusUnknown.name)
        assertEquals("ErrorPasscodeNotSet", CanAuthenticateResponse.ErrorPasscodeNotSet.name)
        assertEquals(
            "ErrorSecurityUpdateRequired",
            CanAuthenticateResponse.ErrorSecurityUpdateRequired.name,
        )
        assertEquals("ErrorUnknown", CanAuthenticateResponse.ErrorUnknown.name)
    }
}
