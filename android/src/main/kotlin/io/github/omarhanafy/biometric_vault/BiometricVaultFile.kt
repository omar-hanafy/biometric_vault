package io.github.omarhanafy.biometric_vault

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.IOException
import javax.crypto.Cipher

/**
 * One encrypted value persisted in the app's private storage.
 *
 * Data lives in `<filesDir>/biometric_vault/<name>.v2.txt`, protected by
 * the Android Keystore key `_CM_<name>_master_key`. Both paths are a
 * compatibility contract with previously written data and must not change.
 */
class BiometricVaultFile(
    context: Context,
    private val baseName: String,
    val options: InitOptions,
) {

    companion object {
        /** Directory inside private storage holding all encrypted files. */
        private const val DIRECTORY_NAME = "biometric_vault"
        private const val FILE_SUFFIX_V2 = ".v2.txt"
    }

    private val masterKeyName = "${baseName}_master_key"
    private val baseDir = File(context.filesDir, DIRECTORY_NAME)
    private val file = File(baseDir, "$baseName$FILE_SUFFIX_V2")
    private val tempFile = File(baseDir, "$baseName$FILE_SUFFIX_V2.tmp")

    private val cryptographyManager = CryptographyManager(context) {
        setUserAuthenticationRequired(options.authenticationRequired)
        if (options.authenticationRequired) {
            configureUserAuthenticationParameters()
        }
    }

    init {
        require(
            baseName.isNotEmpty() &&
                !baseName.contains('/') &&
                !baseName.contains('\\') &&
                baseName != "." &&
                baseName != "..",
        ) {
            "Storage name '$baseName' must be a plain file name without path separators."
        }
        require(!(options.androidAuthenticationValidityDuration == null && !options.androidBiometricOnly)) {
            "androidBiometricOnly must be true when androidAuthenticationValidityDuration is " +
                "null: auth-per-use keys can only be unlocked by a strong biometric."
        }
        StorageLog.d { "Initialized $this with $options" }
    }

    /**
     * Applies the Google recommended key authorization for the configured mode:
     * auth-per-use keys bound to strong biometrics when no validity duration is
     * set, otherwise a time-bound key that also accepts the device credential.
     */
    private fun KeyGenParameterSpec.Builder.configureUserAuthenticationParameters() {
        val validity = options.androidAuthenticationValidityDuration
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (validity == null) {
                setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            } else {
                setUserAuthenticationParameters(
                    validity.inWholeSeconds.toInt(),
                    KeyProperties.AUTH_DEVICE_CREDENTIAL or KeyProperties.AUTH_BIOMETRIC_STRONG,
                )
            }
        } else {
            // Pre Android 11 fallback; -1 requires a biometric for every use.
            @Suppress("DEPRECATION")
            setUserAuthenticationValidityDurationSeconds(
                validity?.inWholeSeconds?.toInt() ?: -1,
            )
        }
    }

    fun cipherForEncrypt(): Cipher =
        cryptographyManager.getInitializedCipherForEncryption(masterKeyName)

    /** Returns null when no stored payload exists (no IV to initialize with). */
    fun cipherForDecrypt(): Cipher? {
        if (!file.exists()) {
            StorageLog.d { "No stored file for $this, no IV to derive a decryption cipher from." }
            return null
        }
        return cryptographyManager.getInitializedCipherForDecryption(masterKeyName, file)
    }

    fun exists(): Boolean = file.exists()

    @Synchronized
    fun writeFile(cipher: Cipher?, content: String) {
        // cipher is null when authentication is not required or a time-bound
        // key is used; in that case the cipher is created on demand.
        val useCipher = cipher ?: cipherForEncrypt()
        val payload = cryptographyManager.encryptData(content, useCipher)
        baseDir.mkdirs()
        if (!baseDir.isDirectory) {
            throw IOException("Unable to create storage directory $baseDir.")
        }
        // Write to a temporary file first so a crash mid-write can never
        // corrupt a previously stored value.
        tempFile.writeBytes(payload)
        if (!tempFile.renameTo(file)) {
            tempFile.delete()
            throw IOException("Unable to move temporary storage file into place for $file.")
        }
        StorageLog.d { "Successfully wrote ${payload.size} bytes to $file." }
    }

    @Synchronized
    fun readFile(cipher: Cipher?): String? {
        if (!file.exists()) {
            StorageLog.d { "File $file does not exist, returning null." }
            return null
        }
        val useCipher = cipher ?: cipherForDecrypt() ?: return null
        return cryptographyManager.decryptData(file.readBytes(), useCipher)
    }

    @Synchronized
    fun deleteFile(): Boolean {
        cryptographyManager.deleteKey(masterKeyName)
        tempFile.delete()
        return file.delete()
    }

    fun dispose() {
        StorageLog.d { "dispose($this)" }
    }

    override fun toString(): String =
        "BiometricVaultFile(masterKeyName='$masterKeyName', file=$file)"
}
