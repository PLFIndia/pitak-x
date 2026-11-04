package dev.khoj.pitaka

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkConstructor
import io.mockk.mockkStatic
import io.mockk.unmockkAll
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BiometricSecretVaultTest {
    private lateinit var activity: FragmentActivity
    private lateinit var biometricManager: BiometricManager
    private lateinit var cipher: Cipher
    private lateinit var key: SecretKey
    private lateinit var keyGenerator: KeyGenerator
    private lateinit var keyStore: KeyStore
    private var callback: BiometricPrompt.AuthenticationCallback? = null
    private lateinit var promptLauncher: (
        FragmentActivity,
        Cipher,
        BiometricPrompt.AuthenticationCallback,
    ) -> Unit

    @Suppress("DEPRECATION")
    @Before
    fun setUp() {
        activity = mockk(relaxed = true)
        biometricManager = mockk()
        cipher = mockk(relaxed = true)
        key = mockk()
        keyGenerator = mockk(relaxed = true)
        keyStore = mockk(relaxed = true)
        mockkStatic(BiometricManager::class, KeyStore::class, KeyGenerator::class, Cipher::class)
        mockkConstructor(KeyGenParameterSpec.Builder::class)
        every { anyConstructed<KeyGenParameterSpec.Builder>().setKeySize(any()) } answers {
            self as KeyGenParameterSpec.Builder
        }
        every { anyConstructed<KeyGenParameterSpec.Builder>().setBlockModes(any()) } answers {
            self as KeyGenParameterSpec.Builder
        }
        every {
            anyConstructed<KeyGenParameterSpec.Builder>().setEncryptionPaddings(any())
        } answers { self as KeyGenParameterSpec.Builder }
        every {
            anyConstructed<KeyGenParameterSpec.Builder>().setRandomizedEncryptionRequired(any())
        } answers { self as KeyGenParameterSpec.Builder }
        every {
            anyConstructed<KeyGenParameterSpec.Builder>().setUserAuthenticationRequired(any())
        } answers { self as KeyGenParameterSpec.Builder }
        every {
            anyConstructed<KeyGenParameterSpec.Builder>().setInvalidatedByBiometricEnrollment(any())
        } answers { self as KeyGenParameterSpec.Builder }
        every {
            anyConstructed<KeyGenParameterSpec.Builder>().setUserAuthenticationParameters(any(), any())
        } answers { self as KeyGenParameterSpec.Builder }
        every {
            anyConstructed<KeyGenParameterSpec.Builder>()
                .setUserAuthenticationValidityDurationSeconds(any())
        } answers { self as KeyGenParameterSpec.Builder }
        every { anyConstructed<KeyGenParameterSpec.Builder>().build() } returns mockk()
        every { BiometricManager.from(activity) } returns biometricManager
        every {
            biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        } returns BiometricManager.BIOMETRIC_SUCCESS
        every { KeyStore.getInstance("AndroidKeyStore") } returns keyStore
        every {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        } returns keyGenerator
        every { keyGenerator.generateKey() } returns key
        every { Cipher.getInstance("AES/GCM/NoPadding") } returns cipher
        promptLauncher = { _, _, promptCallback -> callback = promptCallback }
    }

    @After
    fun tearDown() = unmockkAll()

    private fun vault() = BiometricSecretVault(activity, promptLauncher)

    private fun seal(secret: ByteArray, result: RecordingResult, vault: BiometricSecretVault = vault()) {
        vault.onMethodCall(MethodCall("seal", mapOf("secret" to secret)), result)
    }

    private fun succeed() {
        val authentication = mockk<BiometricPrompt.AuthenticationResult>()
        val crypto = mockk<BiometricPrompt.CryptoObject>()
        every { authentication.cryptoObject } returns crypto
        every { crypto.cipher } returns cipher
        callback!!.onAuthenticationSucceeded(authentication)
    }

    private fun assertWiped(bytes: ByteArray) {
        assertTrue(bytes.all { it == 0.toByte() })
    }

    private class RecordingResult(
        private val expectedPlaintext: ByteArray? = null,
    ) : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var deliveredPlaintext: ByteArray? = null
        var sawExpectedPlaintext = false

        override fun success(result: Any?) {
            value = result
            if (result is ByteArray) {
                deliveredPlaintext = result
                sawExpectedPlaintext = expectedPlaintext?.contentEquals(result) == true
            }
        }

        override fun error(code: String, message: String?, details: Any?) {
            errorCode = code
        }

        override fun notImplemented() = Unit
    }

    @Test
    fun sealSuccessWipesSecretOnlyAfterCipherUse() {
        val secret = byteArrayOf(1, 2, 3, 4)
        every { cipher.doFinal(secret) } returns byteArrayOf(9, 8, 7)
        every { cipher.iv } returns byteArrayOf(3, 2, 1)
        val result = RecordingResult()

        seal(secret, result)
        assertNotNull(callback)
        assertTrue(secret.any { it != 0.toByte() })
        succeed()

        assertNull(result.errorCode)
        assertNotNull(result.value)
        assertWiped(secret)
    }

    @Test
    fun sealCancellationWipesSecret() {
        val secret = byteArrayOf(1, 2, 3, 4)
        val result = RecordingResult()

        seal(secret, result)
        callback!!.onAuthenticationError(BiometricPrompt.ERROR_USER_CANCELED, "cancel")

        assertEquals("cancelled", result.errorCode)
        assertWiped(secret)
    }

    @Test
    fun invalidSealInputWipesSecretBeforeReturning() {
        val secret = ByteArray(65) { 1 }
        val result = RecordingResult()

        seal(secret, result)

        assertEquals("failed", result.errorCode)
        assertNull(callback)
        assertWiped(secret)
    }

    @Test
    fun busySealWipesOnlyTheRejectedSecret() {
        val vault = vault()
        val first = byteArrayOf(1, 2, 3)
        val second = byteArrayOf(4, 5, 6)
        val firstResult = RecordingResult()
        val secondResult = RecordingResult()

        seal(first, firstResult, vault)
        seal(second, secondResult, vault)

        assertEquals("busy", secondResult.errorCode)
        assertWiped(second)
        assertTrue(first.any { it != 0.toByte() })
        callback!!.onAuthenticationError(BiometricPrompt.ERROR_USER_CANCELED, "cancel")
        assertWiped(first)
    }

    @Test
    fun promptConstructionFailureWipesSecret() {
        val vault = BiometricSecretVault(activity) { _, _, _ ->
            throw IllegalStateException("synthetic prompt failure")
        }
        val secret = byteArrayOf(1, 2, 3, 4)
        val result = RecordingResult()

        seal(secret, result, vault)

        assertEquals("unavailable", result.errorCode)
        assertWiped(secret)
    }

    @Test
    fun openSuccessWipesReturnedPlaintextAfterHandoff() {
        val plaintext = byteArrayOf(1, 2, 3, 4)
        val ciphertext = ByteArray(16) { 7 }
        val iv = ByteArray(12) { 2 }
        every { keyStore.getKey(any(), isNull()) } returns key
        every { cipher.doFinal(ciphertext) } answers { plaintext.copyOf() }
        val result = RecordingResult(expectedPlaintext = plaintext)

        vault().onMethodCall(
            MethodCall("open", mapOf("iv" to iv, "ciphertext" to ciphertext)),
            result,
        )
        succeed()

        assertNull(result.errorCode)
        assertTrue(result.sawExpectedPlaintext)
        assertWiped(result.deliveredPlaintext!!)
    }
}
