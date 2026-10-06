package dev.khoj.pitaka

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and two narrow method channels:
 *
 *  - [SCREEN_SECURITY_CHANNEL] — screen-capture protection (#34/F-12). When
 *    the vault is unlocked, borrower names and loan lists render on screen.
 *    Dart toggles `FLAG_SECURE` so the Recents/Overview thumbnail and
 *    screen-cast can't capture that PII. The flag is set while unlocked and
 *    cleared when locked (the Dart side drives the decision via the pure
 *    `shouldSecureForState`).
 *  - [BiometricSecretVault.CHANNEL] — M08: seals/opens the biometric vault
 *    secret under an authentication-bound Keystore key via
 *    `BiometricPrompt.CryptoObject`. See that class for the trust boundary.
 *  - [APP_INFO_CHANNEL] — S35: ONE read-only method (`applicationId`) so
 *    Dart can gate the Play in-app update flow to the `play` flavor. The
 *    F-Droid flavor (`dev.khoj.pitaka.fdroid`) has no Play listing and must
 *    never run the update check; the applicationId is the only per-flavor
 *    identity visible at runtime.
 *
 * No other native surface is exposed.
 */
// FlutterFragmentActivity (not FlutterActivity): BiometricPrompt (both
// local_auth's and BiometricSecretVault's) requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BiometricSecretVault.CHANNEL,
        ).setMethodCallHandler(BiometricSecretVault(this))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_SECURITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_INFO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Read-only, non-sensitive: the app's OWN package identity.
                "applicationId" -> result.success(packageName)
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val SCREEN_SECURITY_CHANNEL = "dev.khoj.pitaka/screen_security"
        const val APP_INFO_CHANNEL = "dev.khoj.pitaka/app_info"
    }
}
