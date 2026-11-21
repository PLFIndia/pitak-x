package dev.khoj.pitaka

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Opens Pitak's own page of the phone's settings (review finding P4-M8,
 * decision D131).
 *
 * Why this exists (beginner note): Android shows its "Allow Pitak to take
 * pictures and record video?" dialog twice at most. After the second
 * "Don't allow" the camera can only be allowed again in the phone's
 * settings, and an app cannot change a permission itself. So the scan page
 * offers a button that opens the right page: Pitak's entry in the phone's
 * settings, from which "Permissions" is one tap away.
 *
 * The contract with Dart (`app_settings_opener.dart` mirrors it):
 *  - one method, `open`, with NO argument. Nothing ever comes FROM Dart, so
 *    there is nothing to validate and nothing Dart could steer: the page
 *    and the app it is about are fixed here;
 *  - the answer is `true` (the page was started) or `false`;
 *  - there is no error answer. No exception text is ever passed on.
 *
 * What is started, in the words of the Android reference
 * (`android.provider.Settings`, `ACTION_APPLICATION_DETAILS_SETTINGS`,
 * added in API level 9): "Activity Action: Show screen of details about a
 * particular application. In some cases, a matching Activity may not exist,
 * so ensure you safeguard against this. Input: The Intent's data URI
 * specifies the application package name to be shown, with the "package"
 * scheme. That is "package:com.my.app". Output: Nothing."
 *
 * The page is started inside the app's own task (no `FLAG_ACTIVITY_NEW_TASK`),
 * so Back leads from the phone's settings to Pitak again.
 *
 * No permission is needed, and nothing is stored, logged or sent. The
 * phone's settings app is told the app's own package name and nothing else.
 *
 * Threading: channel calls arrive on the main thread, which is where an
 * activity is started.
 *
 * Shape and lifetime follow [DeviceResourcesChannel]: made in a field of
 * `MainActivity`, then [attach] and [detach]. Everything Android sits
 * behind [AppSettingsPlatform], so that a plain JUnit test can drive this
 * class.
 */
class AppSettingsChannel internal constructor(
    private val platform: AppSettingsPlatform,
) : MethodChannel.MethodCallHandler {

    /** The real thing: the settings of [activity]'s phone. */
    constructor(activity: Activity) : this(AndroidAppSettingsPlatform(activity))

    private var channel: MethodChannel? = null

    /** Wires the channel onto [engine]. Called from `configureFlutterEngine`. */
    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
    }

    /** Releases the channel. Called from `cleanUpFlutterEngine`. */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // The call's arguments are deliberately never looked at.
            METHOD_OPEN -> result.success(open())
            else -> result.notImplemented()
        }
    }

    /** Starts the page. `false` when it could not be started, for any reason. */
    private fun open(): Boolean = try {
        platform.startPage(ACTION_APP_DETAILS, PACKAGE_SCHEME + platform.ownPackageName())
    } catch (e: Exception) {
        // Fail safe: whatever went wrong, Dart is told "not opened", and
        // the scan page keeps its sentence, which says where the camera
        // can be allowed. The exception's text goes nowhere.
        false
    }

    internal companion object {
        const val CHANNEL = "dev.khoj.pitaka/app_settings"
        const val METHOD_OPEN = "open"

        /** "Show screen of details about a particular application." */
        const val ACTION_APP_DETAILS = Settings.ACTION_APPLICATION_DETAILS_SETTINGS

        /** The scheme of the data URI that names the application. */
        const val PACKAGE_SCHEME = "package:"
    }
}

/**
 * Everything [AppSettingsChannel] needs from Android. The app uses
 * [AndroidAppSettingsPlatform]; unit tests use a fake, so the channel's
 * rules can be tested on a plain JVM.
 */
internal interface AppSettingsPlatform {
    /** The package name of this app (it differs between the two flavours). */
    fun ownPackageName(): String

    /**
     * Starts the activity for [action] with the data URI [data]. Answers
     * `false` when the phone has no activity for it. May throw.
     */
    fun startPage(action: String, data: String): Boolean
}

/**
 * The real [AppSettingsPlatform].
 *
 * It is created in a field of `MainActivity`, BEFORE the activity has a
 * context. So nothing here may touch the activity at construction: the
 * package name is looked up when a call comes in.
 */
private class AndroidAppSettingsPlatform(
    private val activity: Activity,
) : AppSettingsPlatform {

    override fun ownPackageName(): String = activity.packageName

    override fun startPage(action: String, data: String): Boolean = try {
        activity.startActivity(Intent(action, Uri.parse(data)))
        true
    } catch (e: ActivityNotFoundException) {
        // "In some cases, a matching Activity may not exist, so ensure you
        // safeguard against this." (the Android reference, quoted above)
        false
    }
}
