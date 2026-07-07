package io.github.omarhanafy.biometric_vault

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.security.KeyPairGenerator
import javax.crypto.Cipher

class EnvelopePayloadTest {

    private val wrappedKey = ByteArray(256) { it.toByte() }
    private val iv = ByteArray(EnvelopePayload.IV_SIZE_IN_BYTES) { (it + 1).toByte() }
    private val ciphertext = ByteArray(64) { (it * 3).toByte() }

    @Test
    fun `encode and parse round-trip`() {
        val payload = EnvelopePayload.encode(wrappedKey, iv, ciphertext)
        assertEquals(EnvelopePayload.VERSION, payload[0])

        val parts = EnvelopePayload.parse(payload)
        assertArrayEquals(wrappedKey, parts.wrappedKey)
        assertArrayEquals(iv, parts.iv)
        assertArrayEquals(ciphertext, parts.ciphertext)
    }

    @Test
    fun `parse rejects a truncated header`() {
        assertThrows(CorruptedStorageDataException::class.java) {
            EnvelopePayload.parse(byteArrayOf(EnvelopePayload.VERSION, 0))
        }
    }

    @Test
    fun `parse rejects an unsupported version byte`() {
        val payload = EnvelopePayload.encode(wrappedKey, iv, ciphertext)
        payload[0] = 9
        assertThrows(CorruptedStorageDataException::class.java) {
            EnvelopePayload.parse(payload)
        }
    }

    @Test
    fun `parse rejects a payload shorter than its declared sections`() {
        val payload = EnvelopePayload.encode(wrappedKey, iv, ciphertext)
        val truncated = payload.copyOfRange(0, payload.size - ciphertext.size - 1)
        assertThrows(CorruptedStorageDataException::class.java) {
            EnvelopePayload.parse(truncated)
        }
    }
}

class EnvelopeCryptoTest {

    @Test
    fun `silent encrypt round-trips through an RSA unwrap cipher`() {
        // Plain JCE keys stand in for the Android Keystore pair; the format,
        // the OAEP parameters, and the AES-GCM envelope are exactly what the
        // device uses.
        val keyPair = KeyPairGenerator.getInstance("RSA").apply {
            initialize(2048)
        }.generateKeyPair()

        val payload = EnvelopeCrypto.encryptWithPublicKey(keyPair.public, "my secret token")

        val unwrapCipher = Cipher.getInstance(EnvelopeCrypto.RSA_TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, keyPair.private, EnvelopeCrypto.oaepSpec())
        }
        assertEquals("my secret token", EnvelopeCrypto.decrypt(payload, unwrapCipher))
    }

    @Test
    fun `decrypt rejects a tampered ciphertext`() {
        val keyPair = KeyPairGenerator.getInstance("RSA").apply {
            initialize(2048)
        }.generateKeyPair()
        val payload = EnvelopeCrypto.encryptWithPublicKey(keyPair.public, "my secret token")
        payload[payload.size - 1] = (payload[payload.size - 1] + 1).toByte()

        val unwrapCipher = Cipher.getInstance(EnvelopeCrypto.RSA_TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, keyPair.private, EnvelopeCrypto.oaepSpec())
        }
        assertThrows(CorruptedStorageDataException::class.java) {
            EnvelopeCrypto.decrypt(payload, unwrapCipher)
        }
    }

    @Test
    fun `every write uses a fresh data key and IV`() {
        val keyPair = KeyPairGenerator.getInstance("RSA").apply {
            initialize(2048)
        }.generateKeyPair()
        val first = EnvelopeCrypto.encryptWithPublicKey(keyPair.public, "same value")
        val second = EnvelopeCrypto.encryptWithPublicKey(keyPair.public, "same value")

        val firstParts = EnvelopePayload.parse(first)
        val secondParts = EnvelopePayload.parse(second)
        // Random wrap + random IV: identical plaintext must never produce
        // identical payload sections.
        assertEquals(false, firstParts.wrappedKey.contentEquals(secondParts.wrappedKey))
        assertEquals(false, firstParts.iv.contentEquals(secondParts.iv))
    }
}
