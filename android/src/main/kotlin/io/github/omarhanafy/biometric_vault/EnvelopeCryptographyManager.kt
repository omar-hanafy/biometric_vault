package io.github.omarhanafy.biometric_vault

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.KeyStoreException
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/**
 * Envelope payload layout (v3), used by silent-writes storage:
 * `[1 byte version=3][2 byte wrappedKeyLen BE][wrappedKey][12 byte IV][ciphertext + 16 byte tag]`.
 *
 * This layout and the `_EM_` key prefix are a compatibility contract with
 * previously written data and must never change without a migration path.
 */
internal object EnvelopePayload {
    const val VERSION: Byte = 3
    private const val HEADER_SIZE = 1 + 2

    internal const val IV_SIZE_IN_BYTES = 12
    internal const val TAG_SIZE_IN_BYTES = 16

    fun encode(wrappedKey: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray {
        require(wrappedKey.size <= 0xFFFF) { "Wrapped key does not fit the 2 byte length header." }
        require(iv.size == IV_SIZE_IN_BYTES) { "IV must be $IV_SIZE_IN_BYTES bytes." }
        val payload = ByteArray(HEADER_SIZE + wrappedKey.size + iv.size + ciphertext.size)
        payload[0] = VERSION
        payload[1] = (wrappedKey.size ushr 8).toByte()
        payload[2] = (wrappedKey.size and 0xFF).toByte()
        wrappedKey.copyInto(payload, HEADER_SIZE)
        iv.copyInto(payload, HEADER_SIZE + wrappedKey.size)
        ciphertext.copyInto(payload, HEADER_SIZE + wrappedKey.size + iv.size)
        return payload
    }

    class Parts(val wrappedKey: ByteArray, val iv: ByteArray, val ciphertext: ByteArray)

    fun parse(payload: ByteArray): Parts {
        if (payload.size < HEADER_SIZE) {
            throw CorruptedStorageDataException("Envelope payload is truncated (incomplete header).")
        }
        if (payload[0] != VERSION) {
            throw CorruptedStorageDataException(
                "Envelope payload has unsupported version ${payload[0]}.",
            )
        }
        val wrappedKeyLen = ((payload[1].toInt() and 0xFF) shl 8) or (payload[2].toInt() and 0xFF)
        val minimumSize = HEADER_SIZE + wrappedKeyLen + IV_SIZE_IN_BYTES + TAG_SIZE_IN_BYTES
        if (payload.size < minimumSize) {
            throw CorruptedStorageDataException(
                "Envelope payload is truncated (${payload.size} bytes, needs at least $minimumSize).",
            )
        }
        val ivStart = HEADER_SIZE + wrappedKeyLen
        val ciphertextStart = ivStart + IV_SIZE_IN_BYTES
        return Parts(
            wrappedKey = payload.copyOfRange(HEADER_SIZE, ivStart),
            iv = payload.copyOfRange(ivStart, ciphertextStart),
            ciphertext = payload.copyOfRange(ciphertextStart, payload.size),
        )
    }
}

/**
 * The pure cryptography of the envelope scheme, separated from the Android
 * Keystore so it is testable on the JVM: a fresh AES-256-GCM data key
 * encrypts the payload and an RSA-OAEP public key wraps the data key.
 */
internal object EnvelopeCrypto {
    const val RSA_TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"
    private const val AES_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val AES_KEY_SIZE = 256

    /**
     * AndroidKeyStore implements OAEP's MGF1 with SHA-1 regardless of the main
     * digest, so the (provider-independent) encrypt side must pin the same
     * parameters or on-device decryption fails with a padding error.
     */
    fun oaepSpec(): OAEPParameterSpec = OAEPParameterSpec(
        "SHA-256",
        "MGF1",
        MGF1ParameterSpec.SHA1,
        PSource.PSpecified.DEFAULT,
    )

    fun encryptWithPublicKey(publicKey: PublicKey, plaintext: String): ByteArray {
        // Re-encode the key so encryption always runs on the default JCE
        // provider, never accidentally inside the keystore.
        val detachedKey = KeyFactory.getInstance("RSA")
            .generatePublic(X509EncodedKeySpec(publicKey.encoded))

        val dataKey = KeyGenerator.getInstance("AES").apply { init(AES_KEY_SIZE) }.generateKey()
        val aes = Cipher.getInstance(AES_TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, dataKey)
        }
        val ciphertext = aes.doFinal(plaintext.toByteArray(Charsets.UTF_8))

        val rsa = Cipher.getInstance(RSA_TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, detachedKey, oaepSpec())
        }
        val wrappedKey = rsa.doFinal(dataKey.encoded)

        return EnvelopePayload.encode(wrappedKey, aes.iv, ciphertext)
    }

    fun decrypt(payload: ByteArray, unwrapCipher: Cipher): String {
        val parts = EnvelopePayload.parse(payload)
        val dataKeyBytes = try {
            unwrapCipher.doFinal(parts.wrappedKey)
        } catch (e: GeneralSecurityException) {
            throw CorruptedStorageDataException("Envelope data key could not be unwrapped.", e)
        }
        val aes = Cipher.getInstance(AES_TRANSFORMATION).apply {
            init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(dataKeyBytes, "AES"),
                GCMParameterSpec(EnvelopePayload.TAG_SIZE_IN_BYTES * 8, parts.iv),
            )
        }
        return try {
            String(aes.doFinal(parts.ciphertext), Charsets.UTF_8)
        } catch (e: GeneralSecurityException) {
            throw CorruptedStorageDataException(
                "Envelope payload failed the authentication tag check.",
                e,
            )
        }
    }
}

/**
 * Owns the Android Keystore RSA key pairs backing silent-writes storage.
 *
 * The public half encrypts without any user authentication (Android only
 * enforces key authorization on private key operations for asymmetric keys),
 * so writes never prompt; the private half unwraps during reads and carries
 * the same user-authentication parameters as the symmetric master keys.
 */
class EnvelopeCryptographyManager(
    context: Context,
    private val configureKeySpec: KeyGenParameterSpec.Builder.() -> Unit,
) {

    companion object {
        /** Namespace prefix distinguishing envelope key pairs inside the keystore. */
        private const val KEY_PREFIX = "_EM_"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val RSA_KEY_SIZE = 2048
    }

    private val applicationContext = context.applicationContext

    /** Encrypts [plaintext] with the store's public key; never prompts. */
    fun encryptSilently(keyName: String, plaintext: String): ByteArray {
        val payload = EnvelopeCrypto.encryptWithPublicKey(publicKeyFor(keyName), plaintext)
        StorageLog.d { "Silently encrypted ${plaintext.length} chars (${payload.size} bytes payload)." }
        return payload
    }

    /**
     * The RSA unwrap cipher for a read. For auth-per-use keys the caller binds
     * it to the prompt through a `CryptoObject`; for time-bound keys `init`
     * throws `UserNotAuthenticatedException` outside the validity window,
     * which the plugin answers with a prompt and a retry.
     */
    fun getInitializedCipherForUnwrap(keyName: String): Cipher = try {
        Cipher.getInstance(EnvelopeCrypto.RSA_TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, privateKeyFor(keyName), EnvelopeCrypto.oaepSpec())
        }
    } catch (e: KeyPermanentlyInvalidatedException) {
        throw InvalidatedStorageKeyException(
            "The Android Keystore entry for '$keyName' was invalidated.",
            e,
        )
    }

    fun decrypt(payload: ByteArray, unwrapCipher: Cipher): String =
        EnvelopeCrypto.decrypt(payload, unwrapCipher)

    fun deleteKey(keyName: String) {
        try {
            loadKeyStore().deleteEntry(KEY_PREFIX + keyName)
        } catch (e: KeyStoreException) {
            StorageLog.w("Unable to delete key '$KEY_PREFIX$keyName' from the Android Keystore.", e)
        }
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun publicKeyFor(keyName: String): PublicKey {
        val realKeyName = KEY_PREFIX + keyName
        loadKeyStore().getCertificate(realKeyName)?.let { return it.publicKey }
        return generateKeyPair(realKeyName).public
    }

    private fun privateKeyFor(keyName: String): PrivateKey {
        val realKeyName = KEY_PREFIX + keyName
        (loadKeyStore().getKey(realKeyName, null) as? PrivateKey)?.let { return it }
        return generateKeyPair(realKeyName).private
    }

    private fun generateKeyPair(realKeyName: String): KeyPair {
        if (hasStrongBox()) {
            try {
                return generateKeyPair(realKeyName, useStrongBox = true)
            } catch (e: GeneralSecurityException) {
                if (!isStrongBoxUnavailable(e)) throw e
                StorageLog.w("StrongBox reported unavailable, falling back to a TEE backed key.", e)
            } catch (e: RuntimeException) {
                // Some devices wrap StrongBoxUnavailableException in a ProviderException.
                if (!isStrongBoxUnavailable(e)) throw e
                StorageLog.w("StrongBox reported unavailable, falling back to a TEE backed key.", e)
            }
        }
        return generateKeyPair(realKeyName, useStrongBox = false)
    }

    private fun generateKeyPair(realKeyName: String, useStrongBox: Boolean): KeyPair {
        val spec = KeyGenParameterSpec.Builder(
            realKeyName,
            KeyProperties.PURPOSE_DECRYPT,
        ).apply {
            // SHA-1 is additionally authorized because AndroidKeyStore's OAEP
            // uses SHA-1 for MGF1; see EnvelopeCrypto.oaepSpec.
            setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA1)
            setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            setKeySize(RSA_KEY_SIZE)
            if (useStrongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                setIsStrongBoxBacked(true)
            }
            // Note: keys stay invalidated on new biometric enrollment, which is
            // the platform default (setInvalidatedByBiometricEnrollment == true).
            // Invalidation only affects the private (read) half; silent writes
            // keep working and the next read reports the invalidation.
            configureKeySpec()
        }.build()

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEYSTORE)
        generator.initialize(spec)
        return generator.generateKeyPair()
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
