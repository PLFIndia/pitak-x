package dev.khoj.pitaka

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Tells Dart how much free storage and available memory this device has
 * (backup rework BR9, decisions D5, D48 and D50).
 *
 * Why this exists (beginner note): before a backup and before a restore the
 * app says what the run needs and what the phone has. What the phone has
 * can only be asked on the Android side. Dart shows the answer once, in a
 * notice; it never refuses to start because of it.
 *
 * The contract with Dart (`device_resources.dart` mirrors it):
 *  - one method, `read`, with NO argument. Nothing ever comes FROM Dart,
 *    so there is nothing to validate and nothing Dart could steer;
 *  - the answer is a map with up to four entries (the `KEY_` constants at
 *    the bottom). A figure that could not be read is simply left out;
 *  - there is no error answer. No exception text is ever passed on.
 *
 * What is read, in the words of the Android reference:
 *  - `StatFs.getAvailableBytes()`: "The number of bytes that are free on
 *    the file system and available to applications." It is asked for the
 *    app's own files folder. The app's cache folder and its Flutter
 *    documents folder are in the same data directory, so this one figure
 *    stands for everything a backup or a restore writes.
 *    (`StorageManager.getAllocatableBytes()` is NOT used: it counts files
 *    the system "may be willing to delete", and this app writes with plain
 *    file calls that cannot claim those.)
 *  - `ActivityManager.getMemoryInfo()`: `availMem`, "The available memory
 *    on the system"; `threshold`, "The threshold of availMem at which we
 *    consider memory to be low"; `lowMemory`, "Set to true if the system
 *    considers itself to currently be in a low memory situation."
 *
 * No permission is needed for either, and nothing is stored, logged or
 * sent.
 *
 * Threading: channel calls arrive on the main thread. `StatFs` reads from
 * disk, so the read runs on a background thread and the answer is given
 * back on the main thread, where [channel] is also only ever touched.
 *
 * Shape and lifetime follow [PickedDocumentChannel]: made in a field of
 * `MainActivity`, then [attach] and [detach]. Everything Android sits
 * behind [DeviceResourcesPlatform], so that a plain JUnit test can drive
 * this class.
 */
class DeviceResourcesChannel internal constructor(
    private val platform: DeviceResourcesPlatform,
) : MethodChannel.MethodCallHandler {

    /** The real thing: the storage and the memory of [activity]'s device. */
    constructor(activity: Activity) : this(AndroidDeviceResourcesPlatform(activity))

    private var channel: MethodChannel? = null

    /**
     * True once [detach] has run (and until the next [attach]): the Dart
     * side is gone, and nobody may be answered. Only touched on the main
     * thread.
     */
    private var detached = false

    /** Wires the channel onto [engine]. Called from `configureFlutterEngine`. */
    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
        detached = false
    }

    /**
     * Releases the channel. Called from `cleanUpFlutterEngine`. A read that
     * is still running finishes and is then not answered: the Dart side is
     * gone.
     */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        detached = true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // The call's arguments are deliberately never looked at.
            METHOD_READ -> read(result)
            else -> result.notImplemented()
        }
    }

    private fun read(result: MethodChannel.Result) {
        try {
            platform.runInBackground {
                val facts = readFacts()
                platform.runOnMainThread {
                    if (!detached) result.success(facts)
                }
            }
        } catch (e: Exception) {
            // The background thread could not be started. Fail safe: an
            // empty answer means "nothing could be read", and Dart says so.
            result.success(emptyMap<String, Any>())
        }
    }

    /**
     * Runs on the background thread. Touches no state of this object.
     *
     * Each figure is read on its own: when one read fails, the other is
     * still given. A failed read leaves its entries out.
     */
    private fun readFacts(): Map<String, Any> {
        val facts = HashMap<String, Any>()
        try {
            facts[KEY_FREE_STORAGE] = platform.freeStorageBytes()
        } catch (e: Exception) {
            // Deliberately ignored: the figure is left out, which Dart
            // reads as "could not be read".
        }
        try {
            val memory = platform.memory()
            facts[KEY_AVAILABLE_MEMORY] = memory.availableBytes
            facts[KEY_LOW_MEMORY_THRESHOLD] = memory.lowThresholdBytes
            facts[KEY_LOW_MEMORY] = memory.lowNow
        } catch (e: Exception) {
            // Deliberately ignored: see above.
        }
        return facts
    }

    internal companion object {
        const val CHANNEL = "dev.khoj.pitaka/device_resources"
        const val METHOD_READ = "read"

        // The keys of the answer, mirrored one-to-one in the Dart port.
        const val KEY_FREE_STORAGE = "freeStorageBytes"
        const val KEY_AVAILABLE_MEMORY = "availableMemoryBytes"
        const val KEY_LOW_MEMORY_THRESHOLD = "lowMemoryThresholdBytes"
        const val KEY_LOW_MEMORY = "lowMemory"
    }
}

/** What Android says about memory right now (`ActivityManager.MemoryInfo`). */
internal data class MemoryFacts(
    val availableBytes: Long,
    val lowThresholdBytes: Long,
    val lowNow: Boolean,
)

/**
 * Everything [DeviceResourcesChannel] needs from Android. The app uses
 * [AndroidDeviceResourcesPlatform]; unit tests use a fake, so the channel's
 * rules can be tested on a plain JVM.
 */
internal interface DeviceResourcesPlatform {
    /** Free bytes of the file system the app's files are on. May throw. */
    fun freeStorageBytes(): Long

    /** The system's memory state. May throw. */
    fun memory(): MemoryFacts

    /** Runs [work] on a background thread. */
    fun runInBackground(work: () -> Unit)

    /** Runs [work] on the main thread. */
    fun runOnMainThread(work: () -> Unit)
}

/**
 * The real [DeviceResourcesPlatform].
 *
 * It is created in a field of `MainActivity`, BEFORE the activity has a
 * context. So nothing here may touch the activity at construction: the
 * files folder and the activity manager are looked up when a call comes in.
 */
private class AndroidDeviceResourcesPlatform(
    private val activity: Activity,
) : DeviceResourcesPlatform {

    // The constructor of `StatFs` does the read; it throws
    // `IllegalArgumentException` "if the file system access fails".
    override fun freeStorageBytes(): Long = StatFs(activity.filesDir.path).availableBytes

    override fun memory(): MemoryFacts {
        val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return MemoryFacts(info.availMem, info.threshold, info.lowMemory)
    }

    // A thread per read, not a pool: the notice is shown a few times a day
    // at most, and no thread should stay behind for it.
    override fun runInBackground(work: () -> Unit) {
        thread(isDaemon = true, name = "pitak-device-resources") { work() }
    }

    override fun runOnMainThread(work: () -> Unit) {
        activity.runOnUiThread { work() }
    }
}
