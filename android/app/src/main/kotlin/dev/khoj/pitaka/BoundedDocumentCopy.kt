package dev.khoj.pitaka

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

/**
 * Copies a stream into a NEW file and stops at a size cap (backup rework
 * BR5b, decision D8).
 *
 * Why this exists (beginner note): when the user chooses a backup file, the
 * bytes come from another app (Files, a cloud drive, anything installed).
 * That app is foreign code: it may send more than it announced, send without
 * end, or fail half-way. So the copy COUNTS what really arrives and stops the
 * moment the count passes the cap, instead of believing an announced size.
 *
 * This file imports `java.io` only, no Android class, on purpose: plain JUnit
 * can then run every line of it without a phone.
 *
 * The rules:
 *  - the target is created new; an existing file is never replaced;
 *  - the check comes BEFORE the write, so never more than the cap reaches
 *    the disk;
 *  - a file of exactly the cap is accepted, one byte more is "too large";
 *  - on every answer but [Outcome.Copied] the half-written target is deleted
 *    before the answer is given;
 *  - the size in the answer is the count, never what anyone announced.
 *
 * The running count is the pattern of Signal Android's `BackupImporter`,
 * which `bounded_file_read.dart` on the Dart side already credits.
 */
internal object BoundedDocumentCopy {

    /**
     * The highest cap a caller may ask for: 2 GiB.
     *
     * This is a stop for a WRONG caller, not the limit of a backup. The real
     * limit is the cap Dart sends (about 504 MiB today), which is far below.
     */
    const val MAX_BYTES_CEILING: Long = 2L * 1024 * 1024 * 1024

    /** Bytes read per step. The Dart ZIP reader uses the same size. */
    private const val BUFFER_BYTES = 64 * 1024

    /** How a copy ended. */
    sealed interface Outcome {
        /** The whole source is in the target; [bytes] were counted. */
        data class Copied(val bytes: Long) : Outcome

        /** The source holds more than the cap. Nothing is left on disk. */
        object TooLarge : Outcome

        /** The source failed while it was read. Nothing is left on disk. */
        object Unreadable : Outcome

        /**
         * The target could not be created or written (it exists already, the
         * disk is full, …). A file that was there before is left untouched.
         */
        object NotSaved : Outcome
    }

    /**
     * The cap as it came over the method channel, checked.
     *
     * Returns the cap when [argument] is a whole number (`Int` or `Long`,
     * the two types the channel uses for a Dart `int`) from 1 to
     * [MAX_BYTES_CEILING]. Returns null for everything else: missing, text,
     * a fraction, zero, negative, too high.
     */
    fun checkedMaxBytes(argument: Any?): Long? {
        val value = when (argument) {
            is Int -> argument.toLong()
            is Long -> argument
            else -> return null
        }
        return if (value in 1..MAX_BYTES_CEILING) value else null
    }

    /**
     * Copies [source] into the new file [target], at most [maxBytes] bytes.
     *
     * The caller closes [source]. The folder of [target] must exist.
     * Never throws for a bad source or a full disk: see [Outcome].
     *
     * [openOutput] opens the new file for writing. The app always uses the
     * default; a test passes its own to play a disk that fails.
     */
    fun copy(
        source: InputStream,
        target: File,
        maxBytes: Long,
        openOutput: (File) -> OutputStream = { FileOutputStream(it) },
    ): Outcome {
        // Fail closed: a cap below one byte allows nothing.
        if (maxBytes < 1) return Outcome.TooLarge

        // `createNewFile` answers false when the file exists. That file is
        // not ours, so it is neither written nor deleted.
        val created = try {
            target.createNewFile()
        } catch (e: Exception) {
            false
        }
        if (!created) return Outcome.NotSaved

        val outcome = copyInto(source, target, maxBytes, openOutput)
        if (outcome !is Outcome.Copied) {
            // Best effort: the caller removes the whole folder as well.
            target.delete()
        }
        return outcome
    }

    private fun copyInto(
        source: InputStream,
        target: File,
        maxBytes: Long,
        openOutput: (File) -> OutputStream,
    ): Outcome {
        val output = try {
            openOutput(target)
        } catch (e: Exception) {
            return Outcome.NotSaved
        }
        var failure: Outcome? = null
        var total = 0L
        try {
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                // Any exception: the source is another app's code.
                val read = try {
                    source.read(buffer)
                } catch (e: Exception) {
                    failure = Outcome.Unreadable
                    break
                }
                if (read < 0) break
                if (read == 0) {
                    // A stream must give at least one byte or say "end".
                    // One that gives nothing could keep this loop going
                    // for ever, so it counts as broken.
                    failure = Outcome.Unreadable
                    break
                }
                total += read
                // BEFORE the write: the byte that passes the cap never
                // reaches the disk.
                if (total > maxBytes) {
                    failure = Outcome.TooLarge
                    break
                }
                try {
                    output.write(buffer, 0, read)
                } catch (e: Exception) {
                    failure = Outcome.NotSaved
                    break
                }
            }
        } finally {
            try {
                output.close()
            } catch (e: Exception) {
                // A close that fails can mean the last bytes never reached
                // the file. Keep an earlier reason if there is one.
                if (failure == null) failure = Outcome.NotSaved
            }
        }
        return failure ?: Outcome.Copied(total)
    }
}
