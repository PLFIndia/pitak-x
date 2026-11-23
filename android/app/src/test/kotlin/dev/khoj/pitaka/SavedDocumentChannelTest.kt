package dev.khoj.pitaka

import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.mockk
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.OutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Stage 8 (review finding P4-M6): the channel that saves a copy of ONE file
 * of the app where the user says. The system's save window, the place and
 * the threads are played by [FakePlatform]; the app's file and the copy are
 * real.
 *
 * What these tests guard:
 *  - only a file in one of the app's two working folders is ever read,
 *    whatever Dart sends, and nothing but a path is taken from Dart;
 *  - every document this code writes into or deletes was EMPTY when it came
 *    back (D176): a document that holds something is left exactly as it is;
 *  - "saved" is never said for a file that is not whole, and a document
 *    that could not be filled is taken back, or the answer says it was not;
 *  - "saved" is said only after the place was asked whether the bytes are
 *    stored and said yes (D182); a place that says no, and a place that
 *    cannot be asked (D183), is taken back like any failed copy;
 *  - nothing is written for a caller that is not there;
 *  - an answer never carries a path, an address or an exception text.
 */
class SavedDocumentChannelTest {
    @get:Rule
    val temp = TemporaryFolder()

    private lateinit var cache: File
    private lateinit var source: File
    private lateinit var platform: FakePlatform
    private lateinit var channel: SavedDocumentChannel
    private val document: Uri = mockk()

    @Before
    fun setUp() {
        cache = File(temp.root, "cache")
        source = fileIn()
        platform = FakePlatform(cache)
        channel = SavedDocumentChannel(platform)
    }

    private fun bytes(count: Int) = ByteArray(count) { (it % 251).toByte() }

    /** Makes `<cache>/<folder>/run-a/<name>` with [size] bytes. */
    private fun fileIn(
        folder: String = "backup_work",
        name: String = "pitak-backup-02Nov2026-134659.pitabak",
        size: Int = 700,
    ): File {
        val dir = File(File(cache, folder), "run-a").apply { mkdirs() }
        return File(dir, name).apply { writeBytes(bytes(size)) }
    }

    private fun call(arguments: Any? = mapOf("path" to source.path)): Reply {
        val reply = Reply()
        channel.onMethodCall(MethodCall("saveCopy", arguments), reply)
        return reply
    }

    /** A whole save with nothing held back: call, choose a place, copy, answer. */
    private fun save(): Reply {
        val reply = call()
        platform.choose(document)
        return reply
    }

    // --- the call ----------------------------------------------------------

    @Test
    fun `the picker is registered when the channel is made`() {
        assertEquals(1, platform.registrations)
    }

    @Test
    fun `an unknown method is not implemented`() {
        val reply = Reply()
        channel.onMethodCall(MethodCall("deleteEverything", null), reply)

        assertTrue(reply.notImplemented)
        assertEquals(0, platform.pickerOpens)
    }

    @Test
    fun `a bad path is invalid and the picker does not open`() {
        val catalogue = File(temp.root, "databases/pitak.db").apply {
            parentFile!!.mkdirs()
            writeBytes(bytes(50))
        }
        val picked = File(cache, "picked_documents/pick-a/document").apply {
            parentFile!!.mkdirs()
            writeBytes(bytes(50))
        }
        val bad = listOf<Any?>(
            null,
            mapOf<String, Any>(),
            mapOf("path" to 7),
            mapOf("path" to ""),
            mapOf("file" to source.path),
            source.path,
            listOf(source.path),
            mapOf("path" to "backup_work/run-a/${source.name}"),
            mapOf("path" to catalogue.path),
            mapOf("path" to picked.path),
            mapOf("path" to "${source.parent}/../../../databases/pitak.db"),
            mapOf("path" to File(source.parentFile, "missing.pdf").path),
        )
        for (arguments in bad) {
            val reply = call(arguments)

            assertEquals("arguments $arguments", "invalid", reply.code)
        }
        assertEquals(0, platform.pickerOpens)
    }

    @Test
    fun `the save window is asked with the file's own name and the type of its ending`() {
        val files = mapOf(
            fileIn() to "application/octet-stream",
            fileIn("export_work", "pitak-export-20261122.json") to "application/json",
            fileIn("export_work", "pitak-library-20261122.csv") to "text/csv",
            fileIn("export_work", "pitak-donated-ram-sharma-20261122.pdf") to "application/pdf",
        )
        for ((file, type) in files) {
            val reply = call(mapOf("path" to file.path))

            assertEquals(file.name, platform.askedName)
            assertEquals(type, platform.askedType)
            assertEquals(0, reply.answers)
            platform.choose(null)
        }
        assertEquals(4, platform.pickerOpens)
    }

    @Test
    fun `nothing but the path is taken from Dart`() {
        call(
            mapOf(
                "path" to source.path,
                "name" to "evil.apk",
                "type" to "text/html",
                "uri" to "content://somewhere/else",
            ),
        )

        assertEquals(source.name, platform.askedName)
        assertEquals("application/octet-stream", platform.askedType)
    }

    @Test
    fun `a cache folder that cannot be asked for is failed, and the call is over`() {
        platform.cacheFailure = IllegalStateException("no context yet")
        val reply = call()

        assertEquals("failed", reply.code)
        assertEquals(0, platform.pickerOpens)

        platform.cacheFailure = null
        assertEquals(0, call().answers)
    }

    @Test
    fun `no place is cancelled, nothing is touched, and the next call may save again`() {
        val reply = call()
        platform.choose(null)

        assertEquals("cancelled", reply.code)
        assertEquals(0, platform.describes)
        assertEquals(0, platform.opens)
        assertEquals(0, platform.deletes)

        call()
        assertEquals(2, platform.pickerOpens)
    }

    @Test
    fun `a second call while the save window is open is busy`() {
        val first = call()
        val second = call()

        assertEquals("busy", second.code)
        assertEquals(0, first.answers)
        assertEquals(1, platform.pickerOpens)
    }

    @Test
    fun `a second call while the copy runs is busy`() {
        platform.holdBackground = true
        val first = call()
        platform.choose(document)
        val second = call()

        assertEquals("busy", second.code)
        assertEquals(1, platform.pickerOpens)

        platform.runHeldWork()
        assertEquals(1, first.answers)
        assertNull(first.code)
    }

    @Test
    fun `a device without a save window is unavailable, and the call is over`() {
        platform.pickerExists = false
        val reply = call()

        assertEquals("unavailable", reply.code)

        // Not stuck in "busy": the next call reaches the window again.
        platform.pickerExists = true
        assertEquals(0, call().answers)
    }

    @Test
    fun `a save window that cannot be opened is failed, and the call is over`() {
        platform.openingThrows = true
        val reply = call()

        assertEquals("failed", reply.code)

        platform.openingThrows = false
        assertEquals(0, call().answers)
    }

    // --- a place -----------------------------------------------------------

    @Test
    fun `the file is copied whole, and the answer is the place's name and the count`() {
        // The place may give the file another name than the one proposed.
        platform.facts = DocumentFacts("pitak-backup-02Nov2026-134659 (1).pitabak", 0)

        val reply = save()

        assertNull(reply.code)
        val answer = reply.value as Map<*, *>
        assertEquals(setOf("name", "size"), answer.keys)
        assertEquals("pitak-backup-02Nov2026-134659 (1).pitabak", answer["name"])
        assertEquals(700L, answer["size"])
        assertArrayEquals(source.readBytes(), platform.place.bytes())
        assertEquals(1, platform.place.closes)
        assertEquals(0, platform.deletes)
        // D182: "saved" rests on the place's own word, asked once.
        assertEquals(1, platform.asks)
    }

    @Test
    fun `the name in the answer is the cleaned one, and may be missing`() {
        platform.facts = DocumentFacts("my\nbackup\u0000" + "x".repeat(1000), 0)
        val name = (save().value as Map<*, *>)["name"] as String

        assertEquals(255, name.length)
        assertTrue(name.startsWith("mybackupxxx"))

        platform.facts = DocumentFacts(null, 0)
        assertEquals("", (save().value as Map<*, *>)["name"])
    }

    @Test
    fun `a name that cannot be asked after the copy is simply missing`() {
        // The first question (is the document empty?) is answered; the
        // second (what is it called now?) fails.
        platform.describeFailsFromCall = 2

        val answer = save().value as Map<*, *>

        assertEquals("", answer["name"])
        assertEquals(700L, answer["size"])
    }

    @Test
    fun `the copy does not run on the calling thread, and the answer comes on the main thread`() {
        platform.holdBackground = true
        platform.holdMain = true
        val reply = call()
        platform.choose(document)

        // Chosen, but the background thread has not run yet.
        assertEquals(0, platform.describes)
        assertEquals(0, platform.opens)

        platform.runHeldWork(main = false)
        // Copied, but the main thread has not answered yet.
        assertArrayEquals(source.readBytes(), platform.place.bytes())
        assertEquals(0, reply.answers)

        platform.runHeldWork()
        assertEquals(1, reply.answers)
    }

    // --- only an empty document (D176) -------------------------------------

    @Test
    fun `a document that already holds something is not opened, not written and not deleted`() {
        // The system's save window lets the user tap an existing file and
        // say "overwrite"; the app is then handed that file, with content.
        for (size in listOf(1L, 700L, Long.MAX_VALUE)) {
            platform.facts = DocumentFacts("pitak-backup-01Nov2026-090000.pitabak", size)

            val reply = save()

            assertEquals("size $size", "not_empty", reply.code)
            assertNull(reply.value)
        }
        assertEquals(0, platform.opens)
        assertEquals(0, platform.deletes)
        assertEquals(0L, platform.place.written)

        // The call is over: the next one reaches the window again.
        platform.facts = DocumentFacts("new.pitabak", 0)
        assertNull(save().code)
    }

    @Test
    fun `a document whose size the place does not say is left alone as well`() {
        val unknown = listOf<(FakePlatform) -> Unit>(
            { it.facts = DocumentFacts("x.pitabak", null) },
            { it.facts = DocumentFacts("x.pitabak", -1) },
            { it.describeFailure = SecurityException("no") },
        )
        for (way in unknown) {
            setUp()
            way(platform)

            val reply = save()

            assertEquals("not_empty", reply.code)
            assertEquals(0, platform.opens)
            assertEquals(0, platform.deletes)
        }
    }

    // --- failures ----------------------------------------------------------

    @Test
    fun `a place that cannot be opened is not saved, and the empty document is taken back`() {
        val ways = listOf<(FakePlatform) -> Unit>(
            { it.openGivesNothing = true },
            { it.openFailure = SecurityException("access refused") },
            { it.openFailure = java.io.FileNotFoundException("gone") },
        )
        for (way in ways) {
            setUp()
            way(platform)

            val reply = save()

            assertEquals("not_saved", reply.code)
            assertNull(reply.value)
            assertEquals(1, platform.deletes)
        }
    }

    @Test
    fun `a place that fails while it is written, flushed or closed is not saved and taken back`() {
        val places = listOf(
            Place(failWriteAfter = 0),
            Place(flushFails = true),
            Place(closeFails = true),
        )
        for (place in places) {
            setUp()
            platform.place = place

            val reply = save()

            assertEquals("not_saved", reply.code)
            assertNull(reply.value)
            assertEquals(1, platform.deletes)
        }
    }

    @Test
    fun `a place that says the bytes are not stored is not saved, and the document is taken back`() {
        // The look of 2026-11-23: on a full disk every byte was written and
        // counted, the close said nothing, and the file was a hole.
        platform.stored = DocumentCopyOut.Stored.NO

        val reply = save()

        assertEquals("not_saved", reply.code)
        assertNull(reply.value)
        assertEquals(1, platform.asks)
        assertEquals(1, platform.place.closes)
        assertEquals(1, platform.deletes)
    }

    @Test
    fun `a place whose answer fails is not saved either`() {
        platform.storedFailure = java.io.IOException("content://secret/address")

        val reply = save()

        assertEquals("not_saved", reply.code)
        assertNull(reply.value)
        assertEquals(1, platform.deletes)
    }

    @Test
    fun `a place that cannot be asked is unconfirmed, never saved, and taken back`() {
        // D183: the bytes all went, and nothing vouches for them.
        platform.stored = DocumentCopyOut.Stored.CANNOT_TELL

        val reply = save()

        assertEquals("unconfirmed", reply.code)
        assertNull(reply.value)
        assertEquals(700L, platform.place.written)
        assertEquals(1, platform.place.closes)
        assertEquals(1, platform.deletes)
    }

    @Test
    fun `a no or a cannot-tell that cannot be taken back is left behind`() {
        for (stored in listOf(DocumentCopyOut.Stored.NO, DocumentCopyOut.Stored.CANNOT_TELL)) {
            setUp()
            platform.stored = stored
            platform.deleteWorks = false

            val reply = save()

            assertEquals("$stored", "left_behind", reply.code)
            assertEquals(1, platform.deletes)
        }
    }

    @Test
    fun `the app's own file gone when the copy starts is source, and the place is never opened`() {
        // The file waits in the cache while the save window is open, and
        // Android may empty the cache (T12).
        platform.holdBackground = true
        val reply = call()
        platform.choose(document)
        source.delete()

        platform.runHeldWork()

        assertEquals("source", reply.code)
        assertEquals(0, platform.opens)
        // The document was new and empty, so it is taken back.
        assertEquals(1, platform.deletes)
    }

    @Test
    fun `a file that changed since it was checked is source, never saved, and taken back`() {
        for (newSize in listOf(699, 701)) {
            setUp()
            platform.holdBackground = true
            val reply = call()
            platform.choose(document)
            source.writeBytes(bytes(newSize))

            platform.runHeldWork()

            assertEquals("size $newSize", "source", reply.code)
            assertNull(reply.value)
            assertEquals(1, platform.deletes)
        }
    }

    @Test
    fun `a document that cannot be taken back is left behind, whatever failed first`() {
        val failures = listOf<(FakePlatform) -> Unit>(
            { it.place = Place(closeFails = true) },
            { source.delete() },
        )
        val refusals = listOf<(FakePlatform) -> Unit>(
            { it.deleteWorks = false },
            { it.deleteFailure = SecurityException("content://secret may not be deleted") },
        )
        for (failure in failures) {
            for (refusal in refusals) {
                setUp()
                platform.holdBackground = true
                val reply = call()
                platform.choose(document)
                failure(platform)
                refusal(platform)

                platform.runHeldWork()

                assertEquals("left_behind", reply.code)
                assertEquals(1, platform.deletes)
            }
        }
    }

    @Test
    fun `a background thread that takes no work is failed, and the call is over`() {
        platform.backgroundRefuses = true
        val reply = save()

        // Nobody has asked the document for its size, so nothing is said
        // of it and nothing is done to it.
        assertEquals("failed", reply.code)
        assertEquals(0, platform.describes)
        assertEquals(0, platform.opens)
        assertEquals(0, platform.deletes)

        platform.backgroundRefuses = false
        assertNull(save().code)
    }

    // --- nobody waits ------------------------------------------------------

    @Test
    fun `an empty document that arrives when nobody waits is taken back`() {
        // The app was ended while the save window was open and started
        // again: the place comes back, but no Dart call waits for it. A new,
        // empty file with a backup's name must not stay there.
        platform.choose(document)

        assertEquals(1, platform.describes)
        assertEquals(1, platform.deletes)
        assertEquals(0, platform.opens)
    }

    @Test
    fun `a document with content that arrives when nobody waits is left alone`() {
        val notEmpty = listOf<(FakePlatform) -> Unit>(
            { it.facts = DocumentFacts("older-backup.pitabak", 1) },
            { it.facts = DocumentFacts("older-backup.pitabak", null) },
            { it.describeFailure = SecurityException("no") },
        )
        for (way in notEmpty) {
            setUp()
            way(platform)

            platform.choose(document)

            assertEquals(0, platform.deletes)
            assertEquals(0, platform.opens)
        }
    }

    @Test
    fun `no place that arrives when nobody waits does nothing`() {
        platform.choose(null)

        assertEquals(0, platform.describes)
        assertEquals(0, platform.deletes)
    }

    @Test
    fun `taking back when nobody waits never throws`() {
        // Held back and run from here, as the background thread would run
        // it: outside the call that handed the work over. An exception
        // there would end the thread, and with it the app.
        platform.holdBackground = true
        platform.deleteFailure = SecurityException("no")
        platform.choose(document)
        platform.runHeldWork()
        assertEquals(1, platform.deletes)

        // And when the background thread takes no work at all.
        platform.holdBackground = false
        platform.backgroundRefuses = true
        platform.choose(document)
        assertEquals(1, platform.deletes)
    }

    @Test
    fun `an empty document that arrives after detach is taken back, and nobody is answered`() {
        val reply = call()
        channel.detach()
        platform.choose(document)

        assertEquals(0, platform.opens)
        assertEquals(1, platform.deletes)
        assertEquals(0, reply.answers)
    }

    @Test
    fun `a copy that finishes after detach stays where the user put it, and nobody is answered`() {
        platform.holdBackground = true
        val reply = call()
        platform.choose(document)
        channel.detach()

        platform.runHeldWork()

        assertArrayEquals(source.readBytes(), platform.place.bytes())
        assertEquals(0, platform.deletes)
        assertEquals(0, reply.answers)
    }

    @Test
    fun `a copy that fails after detach was taken back, and nobody is answered`() {
        platform.holdBackground = true
        platform.place = Place(closeFails = true)
        val reply = call()
        platform.choose(document)
        channel.detach()

        platform.runHeldWork()

        assertEquals(1, platform.deletes)
        assertEquals(0, reply.answers)
    }

    @Test
    fun `a second result for one call is ignored`() {
        platform.holdBackground = true
        val reply = call()
        platform.choose(document)
        platform.choose(document)
        platform.choose(null)

        platform.runHeldWork()

        assertEquals(1, reply.answers)
        assertNull(reply.code)
        assertEquals(1, platform.opens)
        assertEquals(0, platform.deletes)
    }

    // --- what an answer may say --------------------------------------------

    @Test
    fun `an error is a code with a fixed text and nothing else`() {
        platform.facts = DocumentFacts("secret-name.pitabak", 0)
        platform.openFailure = SecurityException("content://secret/address was refused")

        val reply = save()

        assertEquals("not_saved", reply.code)
        assertEquals("the copy could not be written; the document was removed", reply.message)
        assertNull(reply.details)
        val codes = listOf(
            "cancelled", "not_saved", "source", "left_behind", "not_empty",
            "unconfirmed", "unavailable", "busy", "invalid", "failed", "anything",
        )
        for (code in codes) {
            val text = SavedDocumentChannel.messageFor(code)
            assertFalse(code, text.contains("secret"))
            assertFalse(code, text.contains("content://"))
            assertFalse(code, text.contains("/"))
            assertFalse(code, text.contains("pitak"))
        }
        // Each of the ten codes has a text of its own; a code nobody
        // knows gets the text of "failed".
        val known = codes - "anything"
        assertEquals(known.size, known.map { SavedDocumentChannel.messageFor(it) }.toSet().size)
        assertEquals(
            SavedDocumentChannel.messageFor("failed"),
            SavedDocumentChannel.messageFor("anything"),
        )
    }

    @Test
    fun `a success never carries a path or an address`() {
        val answer = save().value as Map<*, *>

        assertEquals(setOf("name", "size"), answer.keys)
        assertFalse(answer.toString().contains(cache.path))
        assertFalse(answer.toString().contains("run-a"))
    }

    // --- stand-ins ---------------------------------------------------------

    /** Records what Dart would get. */
    private class Reply : MethodChannel.Result {
        var answers = 0
        var value: Any? = null
        var code: String? = null
        var message: String? = null
        var details: Any? = null
        var notImplemented = false

        override fun success(result: Any?) {
            answers++
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            answers++
            code = errorCode
            message = errorMessage
            details = errorDetails
        }

        override fun notImplemented() {
            answers++
            notImplemented = true
        }
    }

    /** Plays the document at the place the user chose: it keeps what it is given. */
    private class Place(
        private val failWriteAfter: Long = -1,
        private val flushFails: Boolean = false,
        private val closeFails: Boolean = false,
    ) : OutputStream() {
        private val kept = ByteArrayOutputStream()
        var written = 0L
        var closes = 0

        fun bytes(): ByteArray = kept.toByteArray()

        override fun write(oneByte: Int) {
            throw UnsupportedOperationException()
        }

        override fun write(buffer: ByteArray, offset: Int, count: Int) {
            if (failWriteAfter in 0..written) throw IOException("the place went away")
            kept.write(buffer, offset, count)
            written += count
        }

        override fun flush() {
            if (flushFails) throw IOException("flush failed")
        }

        override fun close() {
            closes++
            if (closeFails) throw IOException("close failed")
        }
    }

    /** Plays Android: the save window, the document's own app, the threads. */
    private class FakePlatform(private val cache: File) : DocumentSavePlatform {
        var registrations = 0
        var pickerOpens = 0
        var pickerExists = true
        var openingThrows = false
        var askedType: String? = null
        var askedName: String? = null
        var cacheFailure: Exception? = null

        /** What the place says of the document. Size 0: new and empty. */
        var facts = DocumentFacts("pitak-backup-02Nov2026-134659.pitabak", 0)
        var describeFailure: Exception? = null

        /** The describe call from which on asking fails (0: never). */
        var describeFailsFromCall = 0
        var describes = 0

        var place = Place()
        var openGivesNothing = false
        var openFailure: Exception? = null
        var opens = 0

        /** What the place answers when it is asked whether the bytes are stored. */
        var stored = DocumentCopyOut.Stored.YES
        var storedFailure: Exception? = null
        var asks = 0

        var deleteWorks = true
        var deleteFailure: Exception? = null
        var deletes = 0

        var holdBackground = false
        var holdMain = false
        var backgroundRefuses = false
        private val heldBackground = ArrayDeque<() -> Unit>()
        private val heldMain = ArrayDeque<() -> Unit>()

        private var onResult: ((Uri?) -> Unit)? = null

        /** The save window closes with [document] (null: no place chosen). */
        fun choose(document: Uri?) = onResult!!.invoke(document)

        /** Runs what was held back: the background work, then the main thread's. */
        fun runHeldWork(main: Boolean = true) {
            while (heldBackground.isNotEmpty()) heldBackground.removeFirst().invoke()
            if (!main) return
            holdMain = false
            while (heldMain.isNotEmpty()) heldMain.removeFirst().invoke()
        }

        override fun registerPicker(onResult: (Uri?) -> Unit): (String, String) -> Boolean {
            registrations++
            this.onResult = onResult
            return { mimeType, name ->
                if (openingThrows) throw IllegalStateException("launcher is gone")
                if (pickerExists) {
                    pickerOpens++
                    askedType = mimeType
                    askedName = name
                }
                pickerExists
            }
        }

        override fun cacheRoot(): File {
            cacheFailure?.let { throw it }
            return cache
        }

        override fun describe(document: Uri): DocumentFacts {
            describes++
            describeFailure?.let { throw it }
            if (describeFailsFromCall in 1..describes) throw SecurityException("no")
            return facts
        }

        override fun openForWriting(document: Uri): DocumentCopyOut.OpenPlace? {
            opens++
            openFailure?.let { throw it }
            if (openGivesNothing) return null
            return DocumentCopyOut.OpenPlace(place) {
                asks++
                storedFailure?.let { throw it }
                stored
            }
        }

        override fun delete(document: Uri): Boolean {
            deletes++
            deleteFailure?.let { throw it }
            return deleteWorks
        }

        override fun runInBackground(work: () -> Unit) {
            if (backgroundRefuses) throw java.util.concurrent.RejectedExecutionException()
            if (holdBackground) heldBackground.addLast(work) else work()
        }

        override fun runOnMainThread(work: () -> Unit) {
            if (holdMain) heldMain.addLast(work) else work()
        }
    }
}
