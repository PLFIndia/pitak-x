package dev.khoj.pitaka

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import androidx.activity.result.contract.ActivityResultContract
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileDescriptor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Saves a copy of ONE finished file of the app where the user says (review
 * finding P4-M6; decisions D167, D168 and D176). The mirror of
 * [PickedDocumentChannel], which brings a document IN.
 *
 * Why this exists (beginner note): until now a backup or an export could
 * leave the app only through the share sheet, and a phone whose sheet has no
 * app for such a file could not keep it at all. This class opens Android's
 * own "save" window instead, with the file's name filled in, and copies the
 * file into the document the user makes there. Because the app does the
 * copy itself, it can ask the place whether the bytes are stored, and says
 * "saved" only then.
 *
 * The contract with Dart (`channel_document_saver.dart` mirrors it):
 *  - one method, `saveCopy`, with one argument, `path`. No name, no type and
 *    no place ever comes FROM Dart: the name is the file's own, the type
 *    follows its ending, the place is the user's choice;
 *  - success is a map: `name` (what the place calls the file now, for
 *    showing only) and `size` (the bytes counted while copying);
 *  - everything else is an error code with a fixed text (see the constants
 *    at the bottom). No path, no document address and no exception text is
 *    ever put into an answer.
 *
 * Which file may be saved is decided by [DocumentCopyOut.checkedSource],
 * before anything opens: only a finished file in one of the app's two
 * working folders. A mistake on the Dart side can therefore not make this
 * code copy the catalogue, the vault or a key out of the app.
 *
 * ONLY AN EMPTY DOCUMENT (D176). The save window also lets the user tap a
 * file that is already there and answer "overwrite?" with yes; the app is
 * then handed that file, with everything in it ("The returned document may
 * be a newly created document with no content, or it may be an existing
 * document", Android's reference of `ACTION_CREATE_DOCUMENT`). This class
 * never replaces a file. It asks the document for its size first, and only
 * a size of exactly 0 goes on. So every document it writes into, and every
 * document it deletes, held nothing when it came: a save that fails can
 * never cost the user an older backup.
 *
 * A copy that does not end whole takes the (empty, new) document back, so
 * that no unfinished file with a backup's name stays behind; when even that
 * fails, the answer says so ([CODE_LEFT_BEHIND]).
 *
 * THE PLACE IS ASKED (D182, D183). When every byte is written, and before
 * the document is closed, the system is asked to put the bytes on the
 * place's storage now (`fsync`). Only when that worked is the answer
 * "saved". When it failed, the copy failed: on a full disk a place was seen
 * to take every write and the close without a word and to keep a file of
 * the right length with nothing in it. And a place of a kind that has no
 * sync at all (Android lets a place hand over a pipe) cannot vouch for the
 * file: it is taken back too, with a code of its own ([CODE_UNCONFIRMED]).
 *
 * No permission is needed: the user's choice in the system's window grants
 * access to that one document (Android documentation, "Access documents and
 * other files from shared storage"). The access is used once and not kept.
 *
 * Threading: channel calls and the window's result arrive on the main
 * thread, and the small state below is only touched there, so it needs no
 * lock. Everything that talks to the document runs on one background
 * thread.
 */
class SavedDocumentChannel internal constructor(
    private val platform: DocumentSavePlatform,
) : MethodChannel.MethodCallHandler {

    /** The real thing: the system's save window and files of [activity]. */
    constructor(activity: FragmentActivity) : this(AndroidDocumentSavePlatform(activity))

    /** The Dart call that waits for a save, if any. One at a time. */
    private var pending: PendingSave? = null

    private var channel: MethodChannel? = null

    // Registered here, at construction, on purpose: Android only allows it
    // before the activity starts (see `MainActivity`).
    private val openPicker: (String, String) -> Boolean = platform.registerPicker(::onPlaceChosen)

    /** Wires the channel onto [engine]. Called from `configureFlutterEngine`. */
    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
    }

    /**
     * Releases the channel. Called from `cleanUpFlutterEngine`.
     *
     * The Dart side is gone after this, so a call that still waited can no
     * longer be answered. A copy that is running finishes (see [deliver]).
     */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_SAVE_COPY -> saveCopy(call, result)
            else -> result.notImplemented()
        }
    }

    private fun saveCopy(call: MethodCall, result: MethodChannel.Result) {
        val cache = try {
            platform.cacheRoot()
        } catch (e: Exception) {
            reply(result, CODE_FAILED)
            return
        }
        // Everything received over the channel is untrusted: check first.
        val source = DocumentCopyOut.checkedSource(argumentOrNull(call), cache)
        if (source == null) {
            reply(result, CODE_INVALID)
            return
        }
        if (pending != null) {
            reply(result, CODE_BUSY)
            return
        }
        pending = PendingSave(result, source)
        val opened = try {
            openPicker(source.mimeType, source.name)
        } catch (e: Exception) {
            null
        }
        if (opened == true) return
        pending = null
        // false: the device has no app that can show a save window.
        reply(result, if (opened == false) CODE_UNAVAILABLE else CODE_FAILED)
    }

    /** The save window closed. [document] is null when no place was chosen. */
    private fun onPlaceChosen(document: Uri?) {
        val waiting = pending
        if (waiting == null) {
            // Nobody waits: the app was ended and started again while the
            // window was open (or the Flutter side went away). The document
            // exists by now. A new one is empty, and an empty file with a
            // backup's name must not stay at the place.
            if (document != null) takeBackUnowned(document)
            return
        }
        if (waiting.copying) return
        if (document == null) {
            pending = null
            reply(waiting.result, CODE_CANCELLED)
            return
        }
        waiting.copying = true
        try {
            platform.runInBackground {
                val outcome = fill(document, waiting.source)
                platform.runOnMainThread { deliver(waiting, outcome) }
            }
        } catch (e: Exception) {
            // The background thread could not take the work. Nobody has
            // asked the document for its size, so nothing may be said of it
            // and nothing may be done to it: plain "failed".
            pending = null
            reply(waiting.result, CODE_FAILED)
        }
    }

    /**
     * Runs on the background thread. Touches no state of this object.
     *
     * Never throws: every call to the platform is caught where it is made
     * ([isEmpty], [nameOf], [takeBack]; the place's stream inside
     * [DocumentCopyOut.copy]), because each failure has a meaning of its
     * own there.
     */
    private fun fill(document: Uri, source: DocumentCopyOut.Source): SaveOutcome {
        // D176: a document that holds something, or does not say, is left
        // exactly as it is. Not opened, not written, not deleted.
        if (!isEmpty(document)) return SaveOutcome.Refused(CODE_NOT_EMPTY)

        // From here on the document is known to have been empty, so it is
        // ours to fill and ours to take back.
        val copied = DocumentCopyOut.copy(
            source.file,
            source.bytes,
            openPlace = { platform.openForWriting(document) },
        )
        return when (copied) {
            is DocumentCopyOut.Outcome.Copied ->
                SaveOutcome.Saved(nameOf(document), copied.bytes)
            DocumentCopyOut.Outcome.SourceFailed -> takeBack(document, CODE_SOURCE)
            DocumentCopyOut.Outcome.PlaceFailed -> takeBack(document, CODE_NOT_SAVED)
            // D183: every byte went, and the place cannot say that they
            // are stored. Nothing vouches for that file, so it does not
            // stay under a backup's name.
            DocumentCopyOut.Outcome.PlaceCannotConfirm -> takeBack(document, CODE_UNCONFIRMED)
        }
    }

    /**
     * Whether the place says the document holds nothing: a size of exactly
     * 0. A size that is missing, or a place that cannot be asked, is NOT
     * empty: fail closed, an older backup could be behind it.
     */
    private fun isEmpty(document: Uri): Boolean = try {
        platform.describe(document).sizeBytes == 0L
    } catch (e: Exception) {
        false
    }

    /**
     * What the place calls the file now, cleaned for showing. The place may
     * have changed the name that was proposed, and the user may have typed
     * another. A name that cannot be asked is an empty text.
     */
    private fun nameOf(document: Uri): String {
        val raw = try {
            platform.describe(document).name
        } catch (e: Exception) {
            null
        }
        return PickedDocumentChannel.displayNameOf(raw)
    }

    /**
     * Removes a document that came back empty and could not be filled.
     * Answers [code] when it is gone, [CODE_LEFT_BEHIND] when it is not.
     */
    private fun takeBack(document: Uri, code: String): SaveOutcome {
        val gone = try {
            platform.delete(document)
        } catch (e: Exception) {
            false
        }
        return SaveOutcome.Refused(if (gone) code else CODE_LEFT_BEHIND)
    }

    /**
     * A document nobody waits for: taken back when it is empty, left alone
     * when it is not (D176). Best effort; nobody is answered.
     */
    private fun takeBackUnowned(document: Uri) {
        try {
            platform.runInBackground {
                try {
                    if (isEmpty(document)) platform.delete(document)
                } catch (e: Exception) {
                    // Deliberately ignored: there is nobody to tell, and
                    // nothing else that could be tried.
                }
            }
        } catch (e: Exception) {
            // Deliberately ignored, for the same reason.
        }
    }

    /** Back on the main thread: answer Dart, if it is still there. */
    private fun deliver(waiting: PendingSave, outcome: SaveOutcome) {
        // The Flutter side went away while the copy ran. A whole file stays
        // where the user put it; a failed one was taken back already.
        if (pending !== waiting) return
        pending = null
        when (outcome) {
            is SaveOutcome.Saved -> waiting.result.success(
                mapOf(KEY_NAME to outcome.name, KEY_SIZE to outcome.bytes),
            )
            is SaveOutcome.Refused -> reply(waiting.result, outcome.code)
        }
    }

    private fun argumentOrNull(call: MethodCall): Any? = try {
        call.argument<Any>(ARG_PATH)
    } catch (e: Exception) {
        // The arguments were not a map at all.
        null
    }

    private fun reply(result: MethodChannel.Result, code: String) {
        result.error(code, messageFor(code), null)
    }

    private class PendingSave(val result: MethodChannel.Result, val source: DocumentCopyOut.Source) {
        /** True from the moment a place was chosen until Dart is answered. */
        var copying = false
    }

    private sealed interface SaveOutcome {
        class Saved(val name: String, val bytes: Long) : SaveOutcome
        class Refused(val code: String) : SaveOutcome
    }

    internal companion object {
        const val CHANNEL = "dev.khoj.pitaka/saved_document"
        const val METHOD_SAVE_COPY = "saveCopy"
        const val ARG_PATH = "path"

        const val KEY_NAME = "name"
        const val KEY_SIZE = "size"

        // Error codes, mirrored one-to-one in the Dart saver.
        const val CODE_CANCELLED = "cancelled"
        const val CODE_NOT_SAVED = "not_saved"
        const val CODE_SOURCE = "source"
        const val CODE_LEFT_BEHIND = "left_behind"
        const val CODE_NOT_EMPTY = "not_empty"
        const val CODE_UNCONFIRMED = "unconfirmed"
        const val CODE_UNAVAILABLE = "unavailable"
        const val CODE_BUSY = "busy"
        const val CODE_INVALID = "invalid"
        const val CODE_FAILED = "failed"

        /** A fixed text per code. Never built from a name, path or exception. */
        fun messageFor(code: String): String = when (code) {
            CODE_CANCELLED -> "no place was chosen"
            CODE_NOT_SAVED -> "the copy could not be written; the document was removed"
            CODE_SOURCE -> "the file to save could not be read; the document was removed"
            CODE_LEFT_BEHIND -> "the copy failed and the document could not be removed"
            CODE_NOT_EMPTY -> "the chosen document is not empty; nothing was written"
            CODE_UNCONFIRMED -> "the place cannot confirm that the copy is stored; the document was removed"
            CODE_UNAVAILABLE -> "no save window on this device"
            CODE_BUSY -> "a save is already in progress"
            CODE_INVALID -> "invalid path argument"
            else -> "the save failed"
        }
    }
}

/**
 * Everything [SavedDocumentChannel] needs from Android, behind one
 * interface, so that a unit test can play the save window, the place and
 * the threads ([DocumentPickPlatform] does the same for the way in).
 */
internal interface DocumentSavePlatform {
    /**
     * Registers the system's save window; [onResult] gets the document the
     * user made or chose, or null when no place was chosen. Called once,
     * when the channel is made.
     *
     * Returns the function that opens the window for a file of the given
     * type, with the given name filled in. It answers false when the device
     * has no app that can show one.
     */
    fun registerPicker(onResult: (Uri?) -> Unit): (mimeType: String, name: String) -> Boolean

    /** The app's cache folder. Looked up when a call comes in. May throw. */
    fun cacheRoot(): File

    /** Asks the document's app for its name and size. May throw. */
    fun describe(document: Uri): DocumentFacts

    /**
     * Opens [document] for writing: the stream, and the question whether
     * the bytes written into it are stored (D182). May answer null, and may
     * throw.
     */
    fun openForWriting(document: Uri): DocumentCopyOut.OpenPlace?

    /** Deletes [document]. Answers whether it is gone; may throw. */
    fun delete(document: Uri): Boolean

    /** Runs [work] off the main thread. */
    fun runInBackground(work: () -> Unit)

    /** Runs [work] on the main thread. */
    fun runOnMainThread(work: () -> Unit)
}

/**
 * The real [DocumentSavePlatform].
 *
 * It is created in a field of `MainActivity`, BEFORE the activity has a
 * context. So nothing here may touch the activity's files or threads at
 * construction: `cacheDir`, the content resolver and the worker are all
 * looked up when a call comes in.
 */
private class AndroidDocumentSavePlatform(
    private val activity: FragmentActivity,
) : DocumentSavePlatform {

    private val worker: ExecutorService by lazy {
        Executors.newSingleThreadExecutor { work ->
            Thread(work, "pitak-document-save").apply { isDaemon = true }
        }
    }

    override fun registerPicker(onResult: (Uri?) -> Unit): (String, String) -> Boolean {
        val launcher = activity.registerForActivityResult(NewOpenableDocument()) { document ->
            onResult(document)
        }
        return { mimeType, name ->
            try {
                launcher.launch(NewDocumentRequest(mimeType, name))
                true
            } catch (e: ActivityNotFoundException) {
                false
            }
        }
    }

    override fun cacheRoot(): File = activity.cacheDir

    override fun describe(document: Uri): DocumentFacts =
        queryDocumentFacts(activity.contentResolver, document)

    // The two calls `ContentResolver.openOutputStream` makes, under their
    // own names: the stream's descriptor is needed for the question.
    // "w", not "wt": the document is empty (D176), so there is nothing to
    // cut off, and some places fail when they are asked to cut.
    override fun openForWriting(document: Uri): DocumentCopyOut.OpenPlace? {
        val opened = activity.contentResolver.openAssetFileDescriptor(document, "w")
            ?: return null
        val stream = try {
            opened.createOutputStream()
        } catch (e: Exception) {
            try {
                opened.close()
            } catch (ignored: Exception) {
                // Deliberately ignored: the reason that counts is `e`.
            }
            throw e
        }
        return DocumentCopyOut.OpenPlace(stream) { areBytesStored(stream.fd) }
    }

    /**
     * D182: asks the system to write everything that was put into
     * [descriptor] to the place's storage NOW, and says how that went.
     *
     * `Os.fsync` and not `FileDescriptor.sync()`: only the first says WHICH
     * error it was. The Linux manual names two for "this kind of file has
     * no sync" (a pipe, a socket): EINVAL and EROFS. Every other error
     * means the bytes are not stored ("No space left on device" is the one
     * that was seen).
     */
    private fun areBytesStored(descriptor: FileDescriptor): DocumentCopyOut.Stored = try {
        Os.fsync(descriptor)
        DocumentCopyOut.Stored.YES
    } catch (e: ErrnoException) {
        DocumentCopyOut.storedAfterSyncError(
            e.errno,
            noSyncHere = setOf(OsConstants.EINVAL, OsConstants.EROFS),
        )
    }

    override fun delete(document: Uri): Boolean =
        DocumentsContract.deleteDocument(activity.contentResolver, document)

    override fun runInBackground(work: () -> Unit) {
        worker.execute { work() }
    }

    override fun runOnMainThread(work: () -> Unit) {
        activity.runOnUiThread { work() }
    }
}

/** What the save window is asked for: a type, and a name to propose. */
private class NewDocumentRequest(val mimeType: String, val name: String)

/**
 * The system's "create a document" window, for documents that can be opened
 * as a stream.
 *
 * A contract of our own because `ActivityResultContracts.CreateDocument`
 * fixes the type when it is made (this app saves four types through one
 * window) and leaves out `CATEGORY_OPENABLE`, which the Android
 * documentation says a caller "must include" to get a document that can be
 * written as a stream. `OpenableDocument` closes the same gap for the way
 * in.
 */
private class NewOpenableDocument : ActivityResultContract<NewDocumentRequest, Uri?>() {
    override fun createIntent(context: Context, input: NewDocumentRequest): Intent =
        Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(input.mimeType)
            .putExtra(Intent.EXTRA_TITLE, input.name)

    override fun parseResult(resultCode: Int, intent: Intent?): Uri? =
        if (resultCode == Activity.RESULT_OK) intent?.data else null
}
