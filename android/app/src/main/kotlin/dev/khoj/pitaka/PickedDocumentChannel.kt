package dev.khoj.pitaka

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Lets the user choose ONE document and hands Dart a private copy of it
 * that is never larger than a cap (backup rework BR5b, decisions D8 and D19).
 *
 * Why this exists (beginner note): the `file_selector` plugin loads the
 * whole chosen file into memory, about three times over, before any of our
 * own size checks can run (safety check SC1). For a backup of hundreds of
 * megabytes that ends the app. This class opens the same system picker but
 * COPIES the document as a stream into the app's private cache folder,
 * counting bytes while it copies (see [BoundedDocumentCopy]). Dart then
 * works on that file.
 *
 * The contract with Dart (`channel_document_picker.dart` mirrors it):
 *  - one method, `pickAndCopy`, with one argument, `maxBytes`. No path, no
 *    name and no file type ever comes FROM Dart;
 *  - success is a map: `path`, `name`, `size`;
 *  - everything else is an error code with a fixed text (see the constants
 *    at the bottom). No exception text, no file name and no document address
 *    is ever put into an error.
 *
 * Where the copy goes: `<cacheDir>/picked_documents/pick-<random>/document`.
 * The folder name is ours and the file name is fixed, so nothing the other
 * app says can steer where bytes are written. Kotlin only CREATES such a
 * folder (and removes it again when the copy fails). Removing a finished
 * copy is the Dart side's job, because only Dart knows whether a restore is
 * still reading it.
 *
 * The document's display name is passed on for showing only.
 *
 * No permission is needed: the user's choice in the system picker grants
 * read access to that one document (Android documentation, "Access
 * documents and other files from shared storage"). The access is used once,
 * for this copy, and is not kept.
 *
 * Threading: channel calls and the picker's result arrive on the main
 * thread, and the small state below is only touched there, so it needs no
 * lock. The copy itself runs on one background thread.
 *
 * Shape and lifetime follow the play flavor's `AppUpdateChannel`: made in a
 * field of `MainActivity` (the picker must be registered before the activity
 * starts), then [attach] and [detach].
 */
class PickedDocumentChannel internal constructor(
    private val platform: DocumentPickPlatform,
) : MethodChannel.MethodCallHandler {

    /** The real thing: the system picker and files of [activity]. */
    constructor(activity: FragmentActivity) : this(AndroidDocumentPickPlatform(activity))

    /** The Dart call that waits for a document, if any. One at a time. */
    private var pending: PendingPick? = null

    private var channel: MethodChannel? = null

    // Registered here, at construction, on purpose: see the class comment.
    private val openPicker: () -> Boolean = platform.registerPicker(::onDocumentChosen)

    /** Wires the channel onto [engine]. Called from `configureFlutterEngine`. */
    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
    }

    /**
     * Releases the channel. Called from `cleanUpFlutterEngine`.
     *
     * The Dart side is gone after this, so a call that still waited can no
     * longer be answered. A copy that is running finishes and is then
     * deleted (see [deliver]).
     */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_PICK_AND_COPY -> pickAndCopy(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickAndCopy(call: MethodCall, result: MethodChannel.Result) {
        // Everything received over the channel is untrusted: check first.
        val maxBytes = BoundedDocumentCopy.checkedMaxBytes(argumentOrNull(call))
        if (maxBytes == null) {
            reply(result, CODE_INVALID)
            return
        }
        if (pending != null) {
            reply(result, CODE_BUSY)
            return
        }
        pending = PendingPick(result, maxBytes)
        val opened = try {
            openPicker()
        } catch (e: Exception) {
            null
        }
        if (opened == true) return
        pending = null
        // false: the device has no app that can show a picker.
        reply(result, if (opened == false) CODE_UNAVAILABLE else CODE_FAILED)
    }

    /** The picker closed. [document] is null when the user chose nothing. */
    private fun onDocumentChosen(document: Uri?) {
        // Nobody waits: the app was ended and started again while the picker
        // was open. Without an owner a copy would only be a leftover, so
        // nothing is opened and nothing is copied.
        val waiting = pending ?: return
        if (waiting.copying) return
        if (document == null) {
            pending = null
            reply(waiting.result, CODE_CANCELLED)
            return
        }
        waiting.copying = true
        try {
            platform.runInBackground {
                val outcome = try {
                    copyChosen(document, waiting.maxBytes)
                } catch (e: Exception) {
                    PickOutcome.Refused(CODE_FAILED)
                }
                platform.runOnMainThread { deliver(waiting, outcome) }
            }
        } catch (e: Exception) {
            // The background thread could not take the work.
            pending = null
            reply(waiting.result, CODE_FAILED)
        }
    }

    /** Runs on the background thread. Touches no state of this object. */
    private fun copyChosen(document: Uri, maxBytes: Long): PickOutcome {
        // Name and size are what the other app SAYS. Both may be missing,
        // and failing to ask is not a reason to give up.
        val facts = try {
            platform.describe(document)
        } catch (e: Exception) {
            DocumentFacts(name = null, sizeBytes = null)
        }
        // An early no for an honest oversized file, so that hundreds of
        // megabytes are not written first. The count while copying stays
        // the rule: an announced size that is too small changes nothing.
        val announced = facts.sizeBytes
        if (announced != null && announced > maxBytes) {
            return PickOutcome.Refused(CODE_TOO_LARGE)
        }

        val folder = File(platform.picksRoot(), FOLDER_PREFIX + UUID.randomUUID())
        val made = try {
            folder.mkdirs()
        } catch (e: Exception) {
            false
        }
        if (!made) return PickOutcome.Refused(CODE_STORAGE)

        val copied = try {
            val source = platform.open(document)
            if (source == null) {
                BoundedDocumentCopy.Outcome.Unreadable
            } else {
                copyAndClose(source, File(folder, FILE_NAME), maxBytes)
            }
        } catch (e: Exception) {
            // Opening failed (no such document, access refused, …).
            BoundedDocumentCopy.Outcome.Unreadable
        }
        return when (copied) {
            is BoundedDocumentCopy.Outcome.Copied ->
                PickOutcome.Picked(folder, displayNameOf(facts.name), copied.bytes)
            BoundedDocumentCopy.Outcome.TooLarge -> refuse(folder, CODE_TOO_LARGE)
            BoundedDocumentCopy.Outcome.Unreadable -> refuse(folder, CODE_UNREADABLE)
            BoundedDocumentCopy.Outcome.NotSaved -> refuse(folder, CODE_STORAGE)
        }
    }

    private fun copyAndClose(
        source: InputStream,
        target: File,
        maxBytes: Long,
    ): BoundedDocumentCopy.Outcome {
        try {
            return BoundedDocumentCopy.copy(source, target, maxBytes)
        } finally {
            try {
                source.close()
            } catch (e: Exception) {
                // Deliberately ignored: by now every byte is counted and
                // written (or the copy has failed for its own reason). A
                // source that cannot be closed changes neither.
            }
        }
    }

    private fun refuse(folder: File, code: String): PickOutcome {
        removePickFolder(folder)
        return PickOutcome.Refused(code)
    }

    /** Back on the main thread: answer Dart, if it is still there. */
    private fun deliver(waiting: PendingPick, outcome: PickOutcome) {
        if (pending !== waiting) {
            // The Flutter side went away while the copy ran. Nobody can own
            // the copy any more, so it must not stay.
            if (outcome is PickOutcome.Picked) removePickFolder(outcome.folder)
            return
        }
        pending = null
        when (outcome) {
            is PickOutcome.Picked -> waiting.result.success(
                mapOf(
                    KEY_PATH to File(outcome.folder, FILE_NAME).absolutePath,
                    KEY_NAME to outcome.name,
                    KEY_SIZE to outcome.bytes,
                ),
            )
            is PickOutcome.Refused -> reply(waiting.result, outcome.code)
        }
    }

    /**
     * Removes a folder this class made: the one file it may hold, then the
     * folder. Never recursive, so nothing else can be deleted by mistake.
     * Best effort; a leftover is removed by the Dart side's sweep.
     */
    private fun removePickFolder(folder: File) {
        try {
            File(folder, FILE_NAME).delete()
            folder.delete()
        } catch (e: Exception) {
            // Deliberately ignored: see the comment above.
        }
    }

    private fun argumentOrNull(call: MethodCall): Any? = try {
        call.argument<Any>(ARG_MAX_BYTES)
    } catch (e: Exception) {
        // The arguments were not a map at all.
        null
    }

    private fun reply(result: MethodChannel.Result, code: String) {
        result.error(code, messageFor(code), null)
    }

    private class PendingPick(val result: MethodChannel.Result, val maxBytes: Long) {
        /** True from the moment a document was chosen until Dart is answered. */
        var copying = false
    }

    private sealed interface PickOutcome {
        class Picked(val folder: File, val name: String, val bytes: Long) : PickOutcome
        class Refused(val code: String) : PickOutcome
    }

    internal companion object {
        const val CHANNEL = "dev.khoj.pitaka/picked_document"
        const val METHOD_PICK_AND_COPY = "pickAndCopy"
        const val ARG_MAX_BYTES = "maxBytes"

        const val KEY_PATH = "path"
        const val KEY_NAME = "name"
        const val KEY_SIZE = "size"

        /** Folder under the app's cache folder that holds every pick. */
        const val DIRECTORY = "picked_documents"

        /** First part of the name of the folder ONE pick is copied into. */
        const val FOLDER_PREFIX = "pick-"

        /** The fixed name of the copy. Never the document's own name. */
        const val FILE_NAME = "document"

        /** Longest display name that is passed on, in UTF-16 units. */
        const val MAX_NAME_CHARS = 255

        // Error codes, mirrored one-to-one in the Dart picker.
        const val CODE_CANCELLED = "cancelled"
        const val CODE_TOO_LARGE = "too_large"
        const val CODE_UNREADABLE = "unreadable"
        const val CODE_STORAGE = "storage"
        const val CODE_UNAVAILABLE = "unavailable"
        const val CODE_BUSY = "busy"
        const val CODE_INVALID = "invalid"
        const val CODE_FAILED = "failed"

        /** A fixed text per code. Never built from a name, path or exception. */
        fun messageFor(code: String): String = when (code) {
            CODE_CANCELLED -> "no document was chosen"
            CODE_TOO_LARGE -> "the document is larger than the cap"
            CODE_UNREADABLE -> "the document could not be read"
            CODE_STORAGE -> "the copy could not be saved"
            CODE_UNAVAILABLE -> "no document picker on this device"
            CODE_BUSY -> "a pick is already in progress"
            CODE_INVALID -> "invalid maxBytes argument"
            else -> "the pick failed"
        }

        /**
         * The document's name as it may be shown: control characters removed
         * and cut at [MAX_NAME_CHARS]. A missing name is an empty text.
         *
         * Other invisible characters stay: several scripts (Indic ones among
         * them) need joiner characters to be written correctly.
         */
        fun displayNameOf(raw: String?): String {
            val cleaned = raw.orEmpty().filterNot { it.isISOControl() }
            val cut = cleaned.take(MAX_NAME_CHARS)
            // Do not end on the first half of a two-part character.
            return if (cut.isNotEmpty() && cut.last().isHighSurrogate()) cut.dropLast(1) else cut
        }
    }
}

/** What the app a document comes from says about it. Either may be missing. */
internal data class DocumentFacts(val name: String?, val sizeBytes: Long?)

/**
 * Everything [PickedDocumentChannel] needs from Android, behind one
 * interface.
 *
 * Why (beginner note): a unit test runs on the computer, where there is no
 * system picker and no other app to read from. The test hands the channel a
 * stand-in for this interface; the app uses [AndroidDocumentPickPlatform].
 * `BiometricSecretVault` does the same with its prompt.
 */
internal interface DocumentPickPlatform {
    /**
     * Registers the system picker; [onResult] gets the chosen document, or
     * null when the user chose nothing. Called once, when the channel is made.
     *
     * Returns the function that opens the picker. It answers false when the
     * device has no app that can show one.
     */
    fun registerPicker(onResult: (Uri?) -> Unit): () -> Boolean

    /** Asks the document's app for its name and size. May throw. */
    fun describe(document: Uri): DocumentFacts

    /** Opens [document] for reading. May answer null, and may throw. */
    fun open(document: Uri): InputStream?

    /** The folder every pick is copied into (it may not exist yet). */
    fun picksRoot(): File

    /** Runs [work] off the main thread. */
    fun runInBackground(work: () -> Unit)

    /** Runs [work] on the main thread. */
    fun runOnMainThread(work: () -> Unit)
}

/**
 * The real [DocumentPickPlatform].
 *
 * It is created in a field of `MainActivity`, BEFORE the activity has a
 * context. So nothing here may touch the activity's files or threads at
 * construction: `cacheDir`, the content resolver and the worker are all
 * looked up when a call comes in.
 */
private class AndroidDocumentPickPlatform(
    private val activity: FragmentActivity,
) : DocumentPickPlatform {

    private val worker: ExecutorService by lazy {
        Executors.newSingleThreadExecutor { work ->
            Thread(work, "pitak-document-copy").apply { isDaemon = true }
        }
    }

    override fun registerPicker(onResult: (Uri?) -> Unit): () -> Boolean {
        val launcher = activity.registerForActivityResult(OpenableDocument()) { document ->
            onResult(document)
        }
        return {
            try {
                // Every type: Android knows no type for `.pitabak`. This is
                // the picker, and the list of files, the plugin showed.
                launcher.launch(arrayOf("*/*"))
                true
            } catch (e: ActivityNotFoundException) {
                false
            }
        }
    }

    override fun describe(document: Uri): DocumentFacts {
        var name: String? = null
        var size: Long? = null
        val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        activity.contentResolver.query(document, columns, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    name = cursor.getString(nameIndex)
                }
                // "If the size is unknown, the value stored is null"
                // (Android documentation). A Long: a backup may pass 2 GiB.
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        return DocumentFacts(name, size)
    }

    override fun open(document: Uri): InputStream? =
        activity.contentResolver.openInputStream(document)

    override fun picksRoot(): File = File(activity.cacheDir, PickedDocumentChannel.DIRECTORY)

    override fun runInBackground(work: () -> Unit) {
        worker.execute { work() }
    }

    override fun runOnMainThread(work: () -> Unit) {
        activity.runOnUiThread { work() }
    }
}

/**
 * The system's "open a document" picker, limited to documents that can be
 * opened as a stream.
 *
 * `OpenDocument` builds the `ACTION_OPEN_DOCUMENT` request but leaves out
 * `CATEGORY_OPENABLE`, which the Android documentation asks callers to add:
 * without it the picker may offer "virtual" documents that have no bytes.
 */
private class OpenableDocument : ActivityResultContracts.OpenDocument() {
    override fun createIntent(context: Context, input: Array<String>): Intent =
        super.createIntent(context, input).addCategory(Intent.CATEGORY_OPENABLE)
}
