package dev.khoj.pitaka

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Native half of the M08 fix (astra-review.md): the biometric vault secret `S`
 * is sealed under an Android Keystore AES-GCM key that Keystore itself refuses
 * to use unless a BIOMETRIC_STRONG authentication happened for THIS exact
 * operation. Dart used to check a boolean from `local_auth` and then read `S`
 * from ordinary secure storage — two unlinked steps that any code in the app
 * process could bypass. Here the prompt and the cipher are one object
 * ([BiometricPrompt.CryptoObject]): no prompt, no cipher, no `S`.
 *
 * Adapted from the AndroidX security sample "BiometricLoginKotlin"
 * (`CryptographyManager.kt`, android/security-samples, Apache-2.0) with these
 * deliberate changes:
 *  - per-use authentication (no validity window), BIOMETRIC_STRONG only;
 *  - `setInvalidatedByBiometricEnrollment(true)`: adding a fingerprint/face
 *    kills the key → Dart receives `invalidated` → fail closed, re-enrol;
 *  - byte arrays end to end; secrets never become a `String`;
 *  - TEE only (no StrongBox request; user decision D4 — future hardening).
 *
 * Trust boundary: everything received over the channel is untrusted. Argument
 * shapes and lengths are checked before any Keystore call. Error messages
 * never contain secret material.
 *
 * Threading: [MethodChannel] handlers run on the main thread, which is also
 * what [BiometricPrompt] requires; Keystore AES on ≤32 bytes is sub-ms.
 * One prompt at a time — a second request while one is pending is refused
 * (`busy`) rather than queued, mirroring the Dart session FIFO.
 */
class BiometricSecretVault(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    private var inFlight = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "seal" -> seal(call, result)
            "open" -> open(call, result)
            "destroy" -> destroy(result)
            else -> result.notImplemented()
        }
    }

    // --- seal -------------------------------------------------------------

    private fun seal(call: MethodCall, result: MethodChannel.Result) {
        val secret = call.argument<ByteArray>("secret")
        if (secret == null || secret.isEmpty() || secret.size > MAX_SECRET_BYTES) {
            result.error(CODE_FAILED, "invalid secret argument", null)
            return
        }
        if (!canUseStrongBiometric()) {
            secret.fill(0)
            result.error(CODE_UNAVAILABLE, "no strong biometric available", null)
            return
        }
        val cipher: Cipher
        try {
            // A fresh key per enrolment: any previous key (and any sealed value
            // it protected) is superseded. Dart deletes the old ciphertext.
            deleteKey()
            val key = generateKey()
            cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
        } catch (e: Exception) {
            secret.fill(0)
            result.error(mapInitError(e), "cipher init failed", null)
            return
        }
        authenticate(cipher, result) { boundCipher ->
            try {
                val ciphertext = boundCipher.doFinal(secret)
                result.success(mapOf("iv" to boundCipher.iv, "ciphertext" to ciphertext))
            } catch (e: Exception) {
                result.error(CODE_FAILED, "seal failed", null)
            } finally {
                secret.fill(0)
            }
        }
    }

    // --- open -------------------------------------------------------------

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val iv = call.argument<ByteArray>("iv")
        val ciphertext = call.argument<ByteArray>("ciphertext")
        if (iv == null || iv.size != GCM_IV_BYTES ||
            ciphertext == null || ciphertext.size < GCM_TAG_BYTES ||
            ciphertext.size > MAX_SECRET_BYTES + GCM_TAG_BYTES
        ) {
            result.error(CODE_FAILED, "invalid iv/ciphertext argument", null)
            return
        }
        val cipher: Cipher
        try {
            val key = loadKey()
            if (key == null) {
                // Ciphertext exists but its key is gone (device wipe of the
                // Keystore entry, enrolment change on some OEMs): unrecoverable.
                result.error(CODE_INVALIDATED, "key missing", null)
                return
            }
            cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BYTES * 8, iv))
        } catch (e: Exception) {
            result.error(mapInitError(e), "cipher init failed", null)
            return
        }
        authenticate(cipher, result) { boundCipher ->
            try {
                // GCM verifies the tag: a tampered ciphertext throws here and
                // no plaintext is returned.
                result.success(boundCipher.doFinal(ciphertext))
            } catch (e: Exception) {
                result.error(CODE_FAILED, "open failed", null)
            }
        }
    }

    // --- destroy ----------------------------------------------------------

    private fun destroy(result: MethodChannel.Result) {
        try {
            deleteKey()
            result.success(null)
        } catch (e: Exception) {
            result.error(CODE_FAILED, "destroy failed", null)
        }
    }

    // --- prompt bound to the cipher --------------------------------------

    private fun authenticate(
        cipher: Cipher,
        result: MethodChannel.Result,
        onAuthenticated: (Cipher) -> Unit,
    ) {
        if (inFlight) {
            result.error(CODE_BUSY, "authentication already in progress", null)
            return
        }
        inFlight = true
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(res: BiometricPrompt.AuthenticationResult) {
                inFlight = false
                // The ONLY cipher Keystore will now let us use is the one the
                // prompt authorised; a null here means the OS did not bind it.
                val bound = res.cryptoObject?.cipher
                if (bound == null) {
                    result.error(CODE_FAILED, "no bound cipher", null)
                    return
                }
                onAuthenticated(bound)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                inFlight = false
                result.error(mapPromptError(errorCode), "authentication error", null)
            }

            // Called per failed attempt while the prompt stays open; the
            // terminal outcome arrives via onAuthenticationError/Succeeded.
            override fun onAuthenticationFailed() = Unit
        }
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Pitak vault")
            .setSubtitle("Confirm it is you to use your vault key")
            // CryptoObject prompts REQUIRE Class 3 (strong) biometrics; the
            // library throws for WEAK or credential-only combinations.
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .setNegativeButtonText("Cancel")
            .setConfirmationRequired(false)
            .build()
        try {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) {
            inFlight = false
            result.error(CODE_UNAVAILABLE, "prompt could not be shown", null)
        }
    }

    private fun canUseStrongBiometric(): Boolean =
        BiometricManager.from(activity)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS

    // --- Keystore ---------------------------------------------------------

    private fun keyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun loadKey(): SecretKey? =
        keyStore().getKey(KEY_ALIAS, null) as? SecretKey

    private fun deleteKey() {
        val ks = keyStore()
        if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
    }

    private fun generateKey(): SecretKey {
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            // Keystore picks a fresh random IV per encryption (we return it).
            .setRandomizedEncryptionRequired(true)
            // THE M08 property: Keystore refuses this key unless the user just
            // authenticated for this very operation.
            .setUserAuthenticationRequired(true)
            // New fingerprint/face enrolment permanently invalidates the key.
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+: per-use (timeout 0) and strong biometric only.
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            // API 24–29: -1 = every use needs a biometric authentication
            // (the only per-use option on these levels).
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(builder.build())
        return generator.generateKey()
    }

    // --- error mapping (codes are the contract with Dart) -----------------

    private fun mapInitError(e: Exception): String = when (e) {
        is KeyPermanentlyInvalidatedException -> CODE_INVALIDATED
        // Should not happen with a CryptoObject flow, but if Keystore ever
        // demands auth at init time the honest answer is "not authenticated".
        is UserNotAuthenticatedException -> CODE_CANCELLED
        is ProviderException -> CODE_UNAVAILABLE
        else -> CODE_FAILED
    }

    private fun mapPromptError(code: Int): String = when (code) {
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        BiometricPrompt.ERROR_CANCELED,
        BiometricPrompt.ERROR_TIMEOUT -> CODE_CANCELLED
        BiometricPrompt.ERROR_LOCKOUT,
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> CODE_LOCKOUT
        BiometricPrompt.ERROR_NO_BIOMETRICS,
        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_HW_UNAVAILABLE,
        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
        BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED -> CODE_UNAVAILABLE
        else -> CODE_FAILED
    }

    companion object {
        const val CHANNEL = "dev.khoj.pitaka/biometric_secret"

        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "pitaka.vault.biometric.v2"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BYTES = 16
        /** S is 32 bytes today; allow headroom but reject anything absurd. */
        private const val MAX_SECRET_BYTES = 64

        // Error codes — mirrored one-to-one in the Dart store.
        private const val CODE_CANCELLED = "cancelled"
        private const val CODE_LOCKOUT = "lockout"
        private const val CODE_INVALIDATED = "invalidated"
        private const val CODE_UNAVAILABLE = "unavailable"
        private const val CODE_BUSY = "busy"
        private const val CODE_FAILED = "failed"
    }
}
