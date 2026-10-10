package io.github.omarhanafy.biometric_vault

import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

class AuthenticationPolicyTest {
    @Test
    fun `credential fallback checks match biometric-only prompts before Android 11`() {
        for (sdkInt in 24..29) {
            assertEquals(
                BIOMETRIC_STRONG,
                AuthenticationPolicy.allowedAuthenticators(biometricOnly = false, sdkInt),
            )
        }
    }

    @Test
    fun `credential fallback is available starting at Android 11`() {
        assertEquals(
            BIOMETRIC_STRONG or DEVICE_CREDENTIAL,
            AuthenticationPolicy.allowedAuthenticators(biometricOnly = false, sdkInt = 30),
        )
        assertEquals(
            BIOMETRIC_STRONG,
            AuthenticationPolicy.allowedAuthenticators(biometricOnly = true, sdkInt = 30),
        )
    }

    @Test
    fun `unauthenticated storage accepts credential options without an authorization window`() {
        InitOptions(authenticationRequired = false, androidBiometricOnly = false)
            .validateStorageOptions()
    }

    @Test
    fun `authenticated storage requires a validity window for credentials`() {
        assertThrows(IllegalArgumentException::class.java) {
            InitOptions(androidBiometricOnly = false).validateStorageOptions()
        }
        InitOptions(androidBiometricOnly = false, androidAuthenticationValidityDuration = 1.seconds)
            .validateStorageOptions()
    }

    @Test
    fun `validity windows reject nonpositive truncated and overflowing seconds`() {
        for (validity in listOf((-1).seconds, 0.seconds, 999.milliseconds, (Int.MAX_VALUE.toLong() + 1).seconds)) {
            assertThrows("$validity", IllegalArgumentException::class.java) {
                InitOptions(androidAuthenticationValidityDuration = validity).validateStorageOptions()
            }
        }
        InitOptions(androidAuthenticationValidityDuration = Int.MAX_VALUE.seconds)
            .validateStorageOptions()
    }
}
