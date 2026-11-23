package dev.khoj.pitaka

import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream

/**
 * The two halves of "save a copy" that need no Android class (review finding
 * P4-M6, decisions D167 and D168): the rule for WHICH file of the app may
 * leave it, and the copy of that file into the place the user chose.
 *
 * Why this exists (beginner note): [SavedDocumentChannel] is told by Dart
 * which file to save, as a path. Dart is our own code, but a path is only a
 * text, and one mistake in it would be enough to copy the catalogue, the
 * vault or a key out of the app. So this side does not believe the text: it
 * checks that the path names a finished file in one of the two folders the
 * app makes such files in, and nothing else is ever opened.
 *
 * This file imports `java.io` only, no Android class, on purpose: plain JUnit
 * can then run every line of it without a phone ([BoundedDocumentCopy] does
 * the same for the way in).
 *
 * The rules of the path ([checkedSource]):
 *  - it is a text, absolute, without a `.` or `..` part;
 *  - it reads `<cache>/<folder>/<run>/<name>`: the folder is one of
 *    [WORK_FOLDERS], the run is named as `RunFolders` on the Dart side names
 *    a run, and the name is [NAME_STEM] with one of the endings of [TYPES];
 *  - with every link resolved it is still exactly that file. So a link in
 *    place of the file, of the run or of the folder is refused, while the
 *    cache folder itself may be spelled either of the two ways a phone has
 *    for it (`/data/user/0/…` is a link to `/data/data/…`);
 *  - it is a real file, not empty and not above the ceiling.
 *
 * The rules of the copy ([copy]):
 *  - the app's own file is opened FIRST; when that fails the place is never
 *    opened, so nothing at the place is touched;
 *  - the bytes are counted, and the count must equal the size the file had
 *    when it was checked: a file that shrank or grew meanwhile is a failed
 *    source, and never more than was checked is written;
 *  - the place is flushed, ASKED whether the bytes are stored, and closed,
 *    in that order. A flush or a close that fails is a failed copy: the
 *    last bytes may never have arrived. And only a place that answers yes
 *    counts (decision D182): on a full disk a place was seen to take every
 *    write, the flush and the close without a word, and to keep a file of
 *    the right length with nothing in it;
 *  - a place that cannot be asked has an answer of its own, and it is not
 *    "copied" either (decision D183);
 *  - the answer is "copied" only when all of that held.
 */
internal object DocumentCopyOut {

    /**
     * The largest file that is taken: 2 GiB, the ceiling the way in has.
     *
     * A stop for a wrong caller, not the limit of a backup (that is
     * `BackupLimits.maxArchiveBytes` on the Dart side, about 1 GiB).
     */
    const val MAX_SOURCE_BYTES: Long = BoundedDocumentCopy.MAX_BYTES_CEILING

    /** The longest path text that is looked at, in UTF-16 units. */
    const val MAX_PATH_CHARS = 4096

    /** The folder under the cache folder a backup is built in. */
    const val FOLDER_BACKUP = "backup_work"

    /** The folder under the cache folder an export's file is put in. */
    const val FOLDER_EXPORT = "export_work"

    /** The only two folders a file may be taken from. */
    val WORK_FOLDERS: Set<String> = setOf(FOLDER_BACKUP, FOLDER_EXPORT)

    /** What a run folder is called: the same text as in `RunFolders` (Dart). */
    const val RUN_NAME = "run-[A-Za-z0-9_-]{1,64}"

    /** What a file's name may be before its ending. Nothing a path can use. */
    const val NAME_STEM = "[A-Za-z0-9-]{1,120}"

    /**
     * The four endings a file may have, each with the type the system's
     * save window is told. A fixed table: Dart never names a type.
     */
    val TYPES: Map<String, String> = mapOf(
        "pitabak" to "application/octet-stream",
        "json" to "application/json",
        "csv" to "text/csv",
        "pdf" to "application/pdf",
    )

    /** Bytes read per step, as in [BoundedDocumentCopy]. */
    private const val BUFFER_BYTES = 64 * 1024

    private val runName = Regex(RUN_NAME)
    private val nameStem = Regex(NAME_STEM)

    /**
     * A file that passed [checkedSource]: [file] with every link resolved,
     * its own [name], the [mimeType] of its ending, and its size.
     */
    data class Source(val file: File, val name: String, val mimeType: String, val bytes: Long)

    /** How a copy ended. */
    sealed interface Outcome {
        /**
         * Every byte of the file was written, [bytes] were counted, and the
         * place said that they are stored.
         */
        data class Copied(val bytes: Long) : Outcome

        /** The app's own file could not be read, or is not what was checked. */
        object SourceFailed : Outcome

        /**
         * The place could not be opened, written, flushed or closed, or it
         * said that the bytes are NOT stored.
         */
        object PlaceFailed : Outcome

        /**
         * Every byte was written, but the place is of a kind that cannot be
         * asked whether the bytes are stored. Nothing vouches for the file.
         */
        object PlaceCannotConfirm : Outcome
    }

    /** What a place answers when it is asked whether the bytes are stored. */
    enum class Stored {
        /** The place says the bytes are on its storage. */
        YES,

        /** The place says they are not (a full disk, a broken one). */
        NO,

        /** The place is of a kind that has no way to answer. */
        CANNOT_TELL,
    }

    /**
     * The place the user chose, opened for writing: the [stream] to write
     * into, and the question to ask when every byte is written and flushed,
     * BEFORE the stream is closed.
     *
     * Why a question (beginner note): writing into a file usually only
     * puts the bytes into the system's memory; the system writes them to
     * the storage later. When that later step fails, the writes and even
     * the close may have reported nothing. Asking the system to do it NOW
     * ("sync") is the only way to hear about it. Android's own
     * `AtomicFile` does the same: flush, sync, close.
     */
    class OpenPlace(val stream: OutputStream, val areBytesStored: () -> Stored)

    /**
     * What a FAILED sync means, by the error number the system gave.
     *
     * Only an error on the list [noSyncHere] means "this kind of place has
     * no sync" (a pipe, for example). Every other error, known or not, is
     * a no: fail closed. The caller passes the list because the numbers are
     * Android's and this file imports no Android class.
     */
    fun storedAfterSyncError(errno: Int, noSyncHere: Set<Int>): Stored =
        if (errno in noSyncHere) Stored.CANNOT_TELL else Stored.NO

    /**
     * The path as it came over the method channel, checked.
     *
     * Returns the file when [argument] names a finished file of the app in
     * one of [WORK_FOLDERS] under [cacheDir] (the rules are at the top),
     * and null for everything else. Never throws.
     *
     * [maxBytes] is the ceiling. The app always uses the default; a test
     * passes a small one, so that it need not write gigabytes.
     */
    fun checkedSource(
        argument: Any?,
        cacheDir: File,
        maxBytes: Long = MAX_SOURCE_BYTES,
    ): Source? {
        val text = argument as? String ?: return null
        val named = named(text) ?: return null
        return try {
            located(text, named, cacheDir, maxBytes)
        } catch (e: Exception) {
            // Resolving links can fail (a folder that may not be read, a
            // path the system calls invalid). Fail closed.
            null
        }
    }

    /**
     * What a path TEXT says, before any file is looked at: the last three
     * parts of `/…/<folder>/<run>/<name>`, each checked, with the type of
     * the name's ending. Null when the text is not of that form.
     *
     * A function of its own so that a test can see each rule by itself. On
     * a phone a relative path would be read from `/`, which a test on a
     * computer cannot play with files.
     */
    fun named(text: String): Named? {
        if (text.isEmpty() || text.length > MAX_PATH_CHARS) return null
        // A NUL ends a path for the system but not for this code: the two
        // would then speak of different files.
        if (text.indexOf('\u0000') >= 0) return null
        // Absolute: nothing may depend on the folder the app happens to
        // "stand" in.
        if (!text.startsWith("/")) return null
        val parts = text.split('/')
        // No climbing, anywhere in the text.
        if (parts.any { it == "." || it == ".." }) return null
        // "" (before the first slash), at least one part of the cache
        // folder, then folder, run and name.
        if (parts.size < 5) return null
        val name = parts[parts.size - 1]
        val run = parts[parts.size - 2]
        val folder = parts[parts.size - 3]
        val type = typeOf(name) ?: return null
        if (!runName.matches(run)) return null
        if (folder !in WORK_FOLDERS) return null
        return Named(folder, run, name, type)
    }

    /** The checked parts of a path text: see [named]. */
    data class Named(val folder: String, val run: String, val name: String, val mimeType: String)

    /** Where the file REALLY is. May throw: [checkedSource] catches. */
    private fun located(text: String, named: Named, cacheDir: File, maxBytes: Long): Source? {
        // Every link resolved, it must be the very file the text names,
        // under the real cache folder. `expected` is built from the real
        // cache folder and three checked names only.
        val real = File(text).canonicalFile
        val expected = File(File(File(cacheDir.canonicalFile, named.folder), named.run), named.name)
        if (real != expected) return null

        if (!real.isFile) return null
        val bytes = real.length()
        if (bytes < 1 || bytes > maxBytes) return null
        return Source(real, named.name, named.mimeType, bytes)
    }

    /** The type for the ending of [name], or null when the name is not allowed. */
    private fun typeOf(name: String): String? {
        val dot = name.lastIndexOf('.')
        if (dot < 0) return null
        if (!nameStem.matches(name.substring(0, dot))) return null
        return TYPES[name.substring(dot + 1)]
    }

    /**
     * Copies [source] into the stream [openPlace] gives, exactly
     * [expectedBytes] bytes (the size [checkedSource] saw).
     *
     * Never throws for a file that went away or a place that fails: see
     * [Outcome]. Both streams are closed here on every way out.
     *
     * [openPlace] may answer null and may throw; both are a failed place.
     * The question of the place it gives ([OpenPlace.areBytesStored]) is
     * asked once, after a whole copy and its flush, and never after a copy
     * that has failed already; a question that throws is a no.
     * [openSource] opens the app's own file. The app always uses the
     * default; a test passes its own to play a file that fails.
     */
    fun copy(
        source: File,
        expectedBytes: Long,
        openPlace: () -> OpenPlace?,
        openSource: (File) -> InputStream = { FileInputStream(it) },
    ): Outcome {
        // The app's own file first: see the rules at the top.
        val input = try {
            openSource(source)
        } catch (e: Exception) {
            return Outcome.SourceFailed
        }
        try {
            val place = try {
                openPlace()
            } catch (e: Exception) {
                null
            } ?: return Outcome.PlaceFailed
            return copyInto(input, place, expectedBytes)
        } finally {
            try {
                input.close()
            } catch (e: Exception) {
                // Deliberately ignored: by now every byte is counted and
                // written (or the copy has failed for its own reason). Our
                // own file that cannot be closed changes neither.
            }
        }
    }

    private fun copyInto(input: InputStream, place: OpenPlace, expectedBytes: Long): Outcome {
        val output = place.stream
        var failure: Outcome? = null
        var total = 0L
        try {
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                val read = try {
                    input.read(buffer)
                } catch (e: Exception) {
                    failure = Outcome.SourceFailed
                    break
                }
                if (read < 0) break
                if (read == 0) {
                    // A stream must give at least one byte or say "end".
                    // One that gives nothing could keep this loop going
                    // for ever, so it counts as broken.
                    failure = Outcome.SourceFailed
                    break
                }
                total += read
                // BEFORE the write: a file that grew since it was checked
                // is not the file the user was shown, and none of the
                // bytes beyond the checked size reaches the place.
                if (total > expectedBytes) {
                    failure = Outcome.SourceFailed
                    break
                }
                try {
                    output.write(buffer, 0, read)
                } catch (e: Exception) {
                    failure = Outcome.PlaceFailed
                    break
                }
            }
            // The file shrank since it was checked.
            if (failure == null && total != expectedBytes) failure = Outcome.SourceFailed
            if (failure == null) {
                try {
                    output.flush()
                } catch (e: Exception) {
                    failure = Outcome.PlaceFailed
                }
            }
            // D182: every byte is written and flushed, and the stream is
            // still open. Now the place is asked, and only a yes goes on.
            if (failure == null) failure = unlessStored(place)
        } finally {
            try {
                output.close()
            } catch (e: Exception) {
                // A close that fails can mean the last bytes never reached
                // the place. Keep an earlier reason if there is one.
                if (failure == null) failure = Outcome.PlaceFailed
            }
        }
        return failure ?: Outcome.Copied(total)
    }

    /** Null when the place says the bytes are stored; else what went wrong. */
    private fun unlessStored(place: OpenPlace): Outcome? {
        val stored = try {
            place.areBytesStored()
        } catch (e: Exception) {
            // A question that cannot even be asked properly is no answer
            // to rest a "saved" on.
            Stored.NO
        }
        return when (stored) {
            Stored.YES -> null
            Stored.NO -> Outcome.PlaceFailed
            Stored.CANNOT_TELL -> Outcome.PlaceCannotConfirm
        }
    }
}
