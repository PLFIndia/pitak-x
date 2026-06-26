package dev.khoj.pitaka

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and a single narrow method channel for screen-capture
 * protection (#34/F-12).
 *
 * When the vault is unlocked, borrower names and loan lists render on screen.
 * Dart toggles `FLAG_SECURE` through [SCREEN_SECURITY_CHANNEL] so the
 * Recents/Overview thumbnail and screen-cast can't capture that PII. The flag
 * is set while unlocked and cleared when locked (the Dart side drives the
 * decision via the pure `shouldSecureForState`). No other native surface is
 * exposed.
 */
// FlutterFragmentActivity (not FlutterActivity): local_auth's BiometricPrompt
// requires a FragmentActivity host (#34 B2).
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }

    private companion object {
        const val SCREEN_SECURITY_CHANNEL = "dev.khoj.pitaka/screen_security"
    }
}
