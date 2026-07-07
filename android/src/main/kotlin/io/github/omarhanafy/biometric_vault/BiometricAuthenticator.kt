package io.github.omarhanafy.biometric_vault

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import androidx.annotation.MainThread
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import javax.crypto.Cipher

/**
 * Wraps [BiometricManager] and [BiometricPrompt] behind the two flows the
 * plugin needs: capability checks and showing the system authentication
 * prompt, following the patterns recommended by Google:
 * https://developer.android.com/identity/sign-in/biometric-auth
 */
class BiometricAuthenticator(private val context: Context) {

    private val biometricManager by lazy { BiometricManager.from(context) }

    fun canAuthenticate(options: InitOptions): CanAuthenticateResponse {
        if (!options.authenticationRequired) {
            StorageLog.w(
                "canAuthenticate called with authenticationRequired == false, " +
                    "which always reports success. $options",
            )
            return CanAuthenticateResponse.Success
        }
        val response = CanAuthenticateResponse.fromBiometricManagerCode(
            biometricManager.canAuthenticate(allowedAuthenticators(options.androidBiometricOnly)),
        )
        if (response == CanAuthenticateResponse.ErrorNoBiometricEnrolled &&
            !options.androidBiometricOnly &&
            !isDeviceSecure()
        ) {
            // Neither biometrics nor a device credential are set up; mirrors
            // the response reported on iOS and macOS in this situation.
            return CanAuthenticateResponse.ErrorPasscodeNotSet
        }
        return response
    }

    /**
     * Shows the system authentication prompt.
     *
     * [cipher] must only be passed for auth-per-use keys (no validity
     * duration); it is bound to the prompt through a [BiometricPrompt.CryptoObject]
     * and handed back to [onSuccess] once the user authenticated. Time-bound
     * keys authenticate without a crypto object.
     */
    @MainThread
    fun authenticate(
        activity: FragmentActivity,
        cipher: Cipher?,
        promptInfo: AndroidPromptInfo,
        options: InitOptions,
        onSuccess: (cipher: Cipher?) -> Unit,
        onError: ErrorCallback,
    ) {
        StorageLog.d { "authenticate() withCrypto=${cipher != null}" }
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    StorageLog.d { "onAuthenticationError($errorCode, $errString)" }
                    onError(AuthenticationErrorInfo(AuthenticationError.forCode(errorCode), errString))
                }

                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    StorageLog.d { "onAuthenticationSucceeded($result)" }
                    onSuccess(result.cryptoObject?.cipher)
                }

                override fun onAuthenticationFailed() {
                    StorageLog.d { "onAuthenticationFailed()" }
                    // The user was not recognized; the system prompt shows its
                    // own feedback and keeps listening, so there is nothing to do.
                }
            },
        )

        val biometricOnly =
            options.androidBiometricOnly || Build.VERSION.SDK_INT < Build.VERSION_CODES.R
        if (biometricOnly && !options.androidBiometricOnly) {
            StorageLog.d {
                "androidBiometricOnly was false, but device credential fallback " +
                    "requires Android 11 (API ${Build.VERSION_CODES.R}). Ignoring."
            }
        }

        val builder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(promptInfo.title)
            .setSubtitle(promptInfo.subtitle)
            .setDescription(promptInfo.description)
            .setConfirmationRequired(promptInfo.confirmationRequired)

        if (biometricOnly) {
            // A negative button is required (and only allowed) when the device
            // credential is not offered as a fallback.
            builder
                .setAllowedAuthenticators(BIOMETRIC_STRONG)
                .setNegativeButtonText(promptInfo.negativeButton)
        } else {
            builder.setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
        }

        if (cipher != null) {
            prompt.authenticate(builder.build(), BiometricPrompt.CryptoObject(cipher))
        } else {
            prompt.authenticate(builder.build())
        }
    }

    private fun allowedAuthenticators(biometricOnly: Boolean): Int =
        if (biometricOnly) BIOMETRIC_STRONG else BIOMETRIC_STRONG or DEVICE_CREDENTIAL

    private fun isDeviceSecure(): Boolean {
        val keyguardManager =
            context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return keyguardManager?.isDeviceSecure == true
    }
}
