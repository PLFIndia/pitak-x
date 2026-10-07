package dev.khoj.pitaka

import android.app.Activity
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.ActivityResult as PlayActivityResult
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * PLAY FLAVOR ONLY — the Google Play flexible in-app update bridge (S36).
 *
 * Why this file exists (beginner note): the `in_app_update` Flutter plugin
 * we used in S35 bundles Google's proprietary Play Core library into EVERY
 * flavor, which made the F-Droid build non-free. Flutter plugins cannot be
 * limited to one flavor, but plain Kotlin in `src/play/kotlin` can — so the
 * plugin is gone and this class is its replacement. Its twin in
 * `src/fdroid/kotlin` has the same public shape and does nothing, so the
 * F-Droid APK contains zero Play symbols.
 *
 * Adapted from `in_app_update` 5.0.0, `InAppUpdatePlugin.kt` (MIT, Victor
 * Choueiri), with these deliberate changes:
 *  - FLEXIBLE flow only (decision D2, S35): the immediate flow, its
 *    lifecycle-callback resume logic and `performImmediateUpdate` are gone;
 *  - the modern `startUpdateFlowForResult(info, ActivityResultLauncher,
 *    options)` API instead of request codes + `onActivityResult`;
 *  - ONE install-state listener for the object's lifetime (the plugin
 *    registered an extra listener on every start and never removed it);
 *  - `startFlexibleUpdate` resolves when the user ACCEPTS the Play dialog;
 *    download progress is reported over the event channel (the controller
 *    already observes it). The plugin blocked the call until DOWNLOADED;
 *  - the reply to `checkForUpdate` carries only the three fields Dart
 *    reads (data minimization): no package name, staleness or priority.
 *
 * Trust boundary: Dart sends no arguments; nothing crossing the channel is
 * sensitive. Error codes mirror the plugin's so the Dart semantics are
 * unchanged (`USER_DENIED_UPDATE`, `IN_APP_UPDATE_FAILED`,
 * `REQUIRE_CHECK_FOR_UPDATE`, `TASK_FAILURE`).
 *
 * Threading: channel handlers and Play's Task callbacks both land on the
 * main thread, so the small mutable state below needs no locking.
 */
class AppUpdateChannel(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    // Must be registered BEFORE the activity reaches STARTED — MainActivity
    // constructs this object in a field initializer for exactly that reason.
    private val launcher: ActivityResultLauncher<IntentSenderRequest> =
        activity.registerForActivityResult(
            ActivityResultContracts.StartIntentSenderForResult(),
            ::onUpdateFlowResult,
        )

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var installStateSink: EventChannel.EventSink? = null

    private var appUpdateManager: AppUpdateManager? = null
    private var appUpdateInfo: AppUpdateInfo? = null

    /** The Dart caller waiting for the Play consent dialog, if any. */
    private var pendingStart: MethodChannel.Result? = null

    private val installStateListener = InstallStateUpdatedListener { state ->
        installStateSink?.success(state.installStatus())
    }

    /** Wires both channels onto [engine]. Called from `configureFlutterEngine`. */
    fun attach(engine: FlutterEngine) {
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .also { it.setStreamHandler(this) }
    }

    /** Releases the channels and the Play listener. Called from `cleanUpFlutterEngine`. */
    fun detach() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        installStateSink = null
        appUpdateManager?.unregisterListener(installStateListener)
        appUpdateManager = null
        appUpdateInfo = null
        pendingStart = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkForUpdate" -> checkForUpdate(result)
            "startFlexibleUpdate" -> startFlexibleUpdate(result)
            "completeFlexibleUpdate" -> completeFlexibleUpdate(result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        installStateSink = events
    }

    override fun onCancel(arguments: Any?) {
        installStateSink = null
    }

    private fun manager(): AppUpdateManager =
        appUpdateManager ?: AppUpdateManagerFactory.create(activity).also {
            it.registerListener(installStateListener)
            appUpdateManager = it
        }

    private fun checkForUpdate(result: MethodChannel.Result) {
        manager().appUpdateInfo
            .addOnSuccessListener { info ->
                appUpdateInfo = info
                result.success(
                    mapOf(
                        "updateAvailability" to info.updateAvailability(),
                        "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                        "installStatus" to info.installStatus(),
                    ),
                )
            }
            .addOnFailureListener { error ->
                // No Play Store / non-Play install / transient Play error.
                // Dart logs the code only and degrades to "no update".
                result.error("TASK_FAILURE", error.message, null)
            }
    }

    private fun startFlexibleUpdate(result: MethodChannel.Result) {
        val info = appUpdateInfo
        val manager = appUpdateManager
        if (info == null || manager == null) {
            result.error("REQUIRE_CHECK_FOR_UPDATE", "Call checkForUpdate first", null)
            return
        }
        if (pendingStart != null) {
            result.error("IN_APP_UPDATE_FAILED", "An update flow is already pending", null)
            return
        }
        pendingStart = result
        val started = manager.startUpdateFlowForResult(
            info,
            launcher,
            AppUpdateOptions.defaultOptions(AppUpdateType.FLEXIBLE),
        )
        if (!started) {
            pendingStart = null
            result.error("IN_APP_UPDATE_FAILED", "Play refused to start the update flow", null)
        }
    }

    private fun completeFlexibleUpdate(result: MethodChannel.Result) {
        val manager = appUpdateManager
        if (manager == null) {
            result.error("REQUIRE_CHECK_FOR_UPDATE", "Call checkForUpdate first", null)
            return
        }
        // Play installs the downloaded update and restarts the app; the
        // success callback may never run in this process — reply first.
        result.success(null)
        manager.completeUpdate()
    }

    /** The Play consent dialog closed; resolve the waiting Dart call. */
    private fun onUpdateFlowResult(activityResult: ActivityResult) {
        val waiting = pendingStart ?: return
        pendingStart = null
        when (activityResult.resultCode) {
            Activity.RESULT_OK -> waiting.success(null)
            Activity.RESULT_CANCELED ->
                waiting.error("USER_DENIED_UPDATE", "User declined the update", null)
            PlayActivityResult.RESULT_IN_APP_UPDATE_FAILED ->
                waiting.error("IN_APP_UPDATE_FAILED", "Play could not start the update", null)
            else -> waiting.error("IN_APP_UPDATE_FAILED", "Unexpected result", null)
        }
    }

    companion object {
        const val METHOD_CHANNEL = "dev.khoj.pitaka/app_update"
        const val EVENT_CHANNEL = "dev.khoj.pitaka/app_update/install_state"
    }
}
