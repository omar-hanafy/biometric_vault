package io.github.omarhanafy.biometric_vault

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.io.File
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.KeyStoreException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Owns the Android Keystore master keys and the AES/GCM ciphers used to
 * protect storage payloads.
 *
 * Keys are hardware backed (StrongBox where available, falling back to the
 * TEE) and are invalidated when new biometrics are enrolled, which is the
 * platform default recommended by Google.
 *
 * Payload layout (v2): `[12 byte IV][ciphertext][16 byte GCM tag]`.
 * This layout and the `_CM_` key prefix are a compatibility contract with
 * previously written data and must never change without a migration path.
 */
class CryptographyManager(
    context: Context,
    private val configureKeySpec: KeyGenParameterSpec.Builder.() -> Unit,
) {

    companion object {
        /** Namespace prefix distinguishing plugin keys inside the keystore. */
        private const val KEY_PREFIX = "_CM_"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_SIZE = 256

        internal const val IV_SIZE_IN_BYTES = 12
        internal const val TAG_SIZE_IN_BYTES = 16
    }

    private val applicationContext = context.applicationContext

    private val cipherTransformation =
        "${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_GCM}/" +
            KeyProperties.ENCRYPTION_PADDING_NONE

    fun getInitializedCipherForEncryption(keyName: String): Cipher = try {
        createCipher().apply {
            init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey(keyName))
        }
    } catch (e: KeyPermanentlyInvalidatedException) {
        throw InvalidatedStorageKeyException(
            "The Android Keystore entry for '$keyName' was invalidated.",
            e,
        )
    }

    fun getInitializedCipherForDecryption(
        keyName: String,
        initializationVector: ByteArray,
    ): Cipher = try {
        createCipher().apply {
            init(
                Cipher.DECRYPT_MODE,
                getOrCreateSecretKey(keyName),
                GCMParameterSpec(TAG_SIZE_IN_BYTES * 8, initializationVector),
            )
        }
    } catch (e: KeyPermanentlyInvalidatedException) {
        throw InvalidatedStorageKeyException(
            "The Android Keystore entry for '$keyName' was invalidated.",
            e,
        )
    }

    fun getInitializedCipherForDecryption(keyName: String, encryptedDataFile: File): Cipher {
        val iv = ByteArray(IV_SIZE_IN_BYTES)
        val read = encryptedDataFile.inputStream().use { it.read(iv) }
        if (read != IV_SIZE_IN_BYTES) {
            throw CorruptedStorageDataException(
                "Encrypted payload is truncated and does not contain a complete IV.",
            )
        }
        return getInitializedCipherForDecryption(keyName, iv)
    }

    /**
     * Encrypts [plaintext] with a cipher from [getInitializedCipherForEncryption]
     * and returns the complete v2 payload including the IV prefix.
     */
    fun encryptData(plaintext: String, cipher: Cipher): ByteArray {
        val input = plaintext.toByteArray(Charsets.UTF_8)
        val iv = cipher.iv
        if (iv == null || iv.size != IV_SIZE_IN_BYTES) {
            throw IOException(
                "Cipher IV length ${iv?.size} did not match the expected size $IV_SIZE_IN_BYTES.",
            )
        }
        val payload = ByteArray(IV_SIZE_IN_BYTES + input.size + TAG_SIZE_IN_BYTES)
        val written = cipher.doFinal(input, 0, input.size, payload, IV_SIZE_IN_BYTES)
        if (written != input.size + TAG_SIZE_IN_BYTES) {
            throw IOException("Cipher output length did not match the expected AES-GCM payload size.")
        }
        iv.copyInto(payload)
        StorageLog.d { "Encrypted ${input.size} bytes (${payload.size} bytes total payload)." }
        return payload
    }

    /**
     * Decrypts a complete v2 [payload] with a cipher from
     * [getInitializedCipherForDecryption] initialized with the payload's IV.
     */
    fun decryptData(payload: ByteArray, cipher: Cipher): String {
        if (payload.size < IV_SIZE_IN_BYTES + TAG_SIZE_IN_BYTES) {
            throw CorruptedStorageDataException(
                "Encrypted payload is too short to contain both IV and authentication tag.",
            )
        }
        val iv = payload.copyOfRange(0, IV_SIZE_IN_BYTES)
        if (!iv.contentEquals(cipher.iv)) {
            throw CorruptedStorageDataException(
                "Encrypted payload IV does not match the initialized cipher IV.",
            )
        }
        return try {
            val plaintext = cipher.doFinal(payload, IV_SIZE_IN_BYTES, payload.size - IV_SIZE_IN_BYTES)
            String(plaintext, Charsets.UTF_8)
        } catch (e: AEADBadTagException) {
            throw CorruptedStorageDataException(
                "Encrypted payload failed the authentication tag check.",
                e,
            )
        } catch (e: GeneralSecurityException) {
            throw CorruptedStorageDataException(
                "Encrypted payload could not be decrypted safely.",
                e,
            )
        }
    }

    fun deleteKey(keyName: String) {
        val keyStore = loadKeyStore()
        try {
            keyStore.deleteEntry(KEY_PREFIX + keyName)
        } catch (e: KeyStoreException) {
            StorageLog.w("Unable to delete key '$KEY_PREFIX$keyName' from the Android Keystore.", e)
        }
    }

    private fun createCipher(): Cipher = Cipher.getInstance(cipherTransformation)

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun getOrCreateSecretKey(keyName: String): SecretKey {
        val realKeyName = KEY_PREFIX + keyName
        loadKeyStore().getKey(realKeyName, null)?.let { return it as SecretKey }
        return generateSecretKey(realKeyName)
    }

    private fun generateSecretKey(realKeyName: String): SecretKey {
        if (hasStrongBox()) {
            try {
                return generateSecretKey(realKeyName, useStrongBox = true)
            } catch (e: GeneralSecurityException) {
                if (!isStrongBoxUnavailable(e)) throw e
                StorageLog.w("StrongBox reported unavailable, falling back to a TEE backed key.", e)
            } catch (e: RuntimeException) {
                // Some devices wrap StrongBoxUnavailableException in a ProviderException.
                if (!isStrongBoxUnavailable(e)) throw e
                StorageLog.w("StrongBox reported unavailable, falling back to a TEE backed key.", e)
            }
        }
        return generateSecretKey(realKeyName, useStrongBox = false)
    }

    private fun generateSecretKey(realKeyName: String, useStrongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            realKeyName,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        ).apply {
            setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            setKeySize(KEY_SIZE)
            if (useStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                setIsStrongBoxBacked(true)
            }
            // Note: keys stay invalidated on new biometric enrollment, which is
            // the platform default (setInvalidatedByBiometricEnrollment == true).
            configureKeySpec()
        }.build()

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun hasStrongBox(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            applicationContext.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)

    private fun isStrongBoxUnavailable(error: Throwable): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        var current: Throwable? = error
        while (current != null) {
            if (current is StrongBoxUnavailableException) return true
            current = current.cause
        }
        return false
    }
}
