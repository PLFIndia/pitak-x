package dev.khoj.pitaka

import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.mockk
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * BR5b: the channel that lets the user choose a document and copies it
 * under a cap. The system picker and the other app are played by
 * [FakePlatform]; the copy and the files are real.
 *
 * What these tests guard:
 *  - nothing is copied for a caller that is not there (any more);
 *  - nothing a document's app says decides where bytes go or how many;
 *  - every way out but success leaves no folder behind;
 *  - an answer never carries a name, a path or an exception text.
 */
class PickedDocumentChannelTest {
    @get:Rule
    val temp = TemporaryFolder()

    private lateinit var root: File
    private lateinit var platform: FakePlatform
    private lateinit var channel: PickedDocumentChannel
    private val document: Uri = mockk()

    @Before
    fun setUp() {
        root = File(temp.root, PickedDocumentChannel.DIRECTORY)
        platform = FakePlatform(root)
        channel = PickedDocumentChannel(platform)
    }

    private fun call(arguments: Any? = mapOf("maxBytes" to 1000)): Reply {
        val reply = Reply()
        channel.onMethodCall(MethodCall("pickAndCopy", arguments), reply)
        return reply
    }

    /** A whole pick with nothing held back: call, choose, copy, answer. */
    private fun pick(maxBytes: Long = 1000): Reply {
        val reply = call(mapOf("maxBytes" to maxBytes))
        platform.choose(document)
        return reply
    }

    private fun folders(): List<File> = root.listFiles()?.toList().orEmpty()

    private fun bytes(count: Int) = ByteArray(count) { (it % 251).toByte() }

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
    fun `a bad cap is invalid and the picker does not open`() {
        val bad = listOf<Any?>(
            null,
            mapOf<String, Any>(),
            mapOf("maxBytes" to 0),
            mapOf("maxBytes" to -5),
            mapOf("maxBytes" to "1000"),
            mapOf("maxBytes" to 1000.0),
            mapOf("maxBytes" to BoundedDocumentCopy.MAX_BYTES_CEILING + 1),
            mapOf("max" to 1000),
            "1000",
            listOf(1000),
        )
        for (arguments in bad) {
            val reply = call(arguments)

            assertEquals("arguments $arguments", "invalid", reply.code)
        }
        assertEquals(0, platform.pickerOpens)
    }

    @Test
    fun `a call opens the picker once and waits`() {
        val reply = call()

        assertEquals(1, platform.pickerOpens)
        assertEquals(0, reply.answers)
    }

    @Test
    fun `no document is cancelled, and the next call may pick again`() {
        val reply = call()
        platform.choose(null)

        assertEquals("cancelled", reply.code)
        assertEquals(0, platform.opens)
        assertTrue(folders().isEmpty())

        call()
        assertEquals(2, platform.pickerOpens)
    }

    @Test
    fun `a second call while the picker is open is busy`() {
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
    fun `a device without a picker is unavailable, and the call is over`() {
        platform.pickerExists = false
        val reply = call()

        assertEquals("unavailable", reply.code)

        // Not stuck in "busy": the next call reaches the picker again.
        platform.pickerExists = true
        assertEquals(0, call().answers)
    }

    @Test
    fun `a picker that cannot be opened is failed, and the call is over`() {
        platform.openingThrows = true
        val reply = call()

        assertEquals("failed", reply.code)

        platform.openingThrows = false
        assertEquals(0, call().answers)
    }

    // --- a document --------------------------------------------------------

    @Test
    fun `a document is copied into a folder of our own name`() {
        val data = bytes(700)
        platform.content = data
        platform.facts = DocumentFacts("Pitak-backup-20261111.pitabak", 700)

        val reply = pick()

        assertNull(reply.code)
        val answer = reply.value as Map<*, *>
        assertEquals(setOf("path", "name", "size"), answer.keys)
        assertEquals("Pitak-backup-20261111.pitabak", answer["name"])
        assertEquals(700L, answer["size"])

        val copy = File(answer["path"] as String)
        assertArrayEquals(data, copy.readBytes())
        // The shape the Dart side accepts: <root>/pick-<random>/document.
        assertEquals("document", copy.name)
        assertEquals(root.absoluteFile, copy.parentFile!!.parentFile)
        assertTrue(Regex("^pick-[A-Za-z0-9_-]{1,64}$").matches(copy.parentFile!!.name))
        assertEquals(listOf(copy.parentFile), folders())
        assertEquals(listOf(copy), copy.parentFile!!.listFiles()!!.toList())
    }

    @Test
    fun `the name of the document never decides the file name`() {
        platform.facts = DocumentFacts("../../../databases/app.db", null)

        val answer = pick().value as Map<*, *>

        assertEquals("document", File(answer["path"] as String).name)
        assertEquals("../../../databases/app.db", answer["name"])
        assertEquals(1, folders().size)
    }

    @Test
    fun `the name in the answer is the cleaned one`() {
        platform.facts = DocumentFacts("my\nbackup\u0000" + "x".repeat(1000), null)

        val name = (pick().value as Map<*, *>)["name"] as String

        assertEquals(255, name.length)
        assertTrue(name.startsWith("mybackupxxx"))
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
        assertTrue(folders().isEmpty())

        platform.runHeldWork(main = false)
        // Copied, but the main thread has not answered yet.
        assertEquals(1, folders().size)
        assertEquals(0, reply.answers)

        platform.runHeldWork()
        assertEquals(1, reply.answers)
    }

    @Test
    fun `two picks get two folders, and the second does not remove the first`() {
        val first = File((pick().value as Map<*, *>)["path"] as String)
        val second = File((pick().value as Map<*, *>)["path"] as String)

        assertNotEquals(first.parentFile, second.parentFile)
        assertTrue(first.exists())
        assertTrue(second.exists())
    }

    @Test
    fun `the source is closed after the copy`() {
        pick()

        assertEquals(1, platform.closes)
    }

    // --- sizes -------------------------------------------------------------

    @Test
    fun `exactly the cap is copied, one byte more is too large`() {
        platform.content = bytes(1000)
        assertEquals(1000L, (pick(1000).value as Map<*, *>)["size"])

        val before = folders().size
        platform.content = bytes(1001)
        val reply = pick(1000)

        assertEquals("too_large", reply.code)
        assertEquals(before, folders().size)
    }

    @Test
    fun `an announced size above the cap is too large without opening the document`() {
        platform.facts = DocumentFacts("big.pitabak", 1001)
        platform.content = bytes(10)

        val reply = pick(1000)

        assertEquals("too_large", reply.code)
        assertEquals(0, platform.opens)
        assertTrue(folders().isEmpty())
    }

    @Test
    fun `an announced size that is too small does not help - the count decides`() {
        platform.facts = DocumentFacts("liar.pitabak", 10)
        platform.content = bytes(5000)

        val reply = pick(1000)

        assertEquals("too_large", reply.code)
        assertTrue(folders().isEmpty())
        assertEquals(1, platform.closes)
    }

    @Test
    fun `the size in the answer is the count, not what was announced`() {
        for (announced in listOf<Long?>(900, 0, -1, Long.MIN_VALUE, null)) {
            platform.facts = DocumentFacts("x.pitabak", announced)
            platform.content = bytes(300)

            val reply = pick(1000)

            assertEquals("announced $announced", 300L, (reply.value as Map<*, *>)["size"])
        }
    }

    // --- failures ----------------------------------------------------------

    @Test
    fun `a document that cannot be opened is unreadable and leaves no folder`() {
        val ways = listOf<(FakePlatform) -> Unit>(
            { it.openGivesNothing = true },
            { it.openFailure = SecurityException("access refused") },
            { it.openFailure = java.io.FileNotFoundException("gone") },
        )
        for (way in ways) {
            setUp()
            way(platform)

            val reply = pick()

            assertEquals("unreadable", reply.code)
            assertTrue(folders().isEmpty())
        }
    }

    @Test
    fun `a document that fails while it is read is unreadable and leaves no folder`() {
        platform.content = bytes(500)
        platform.readFailureAfterBytes = 200

        val reply = pick()

        assertEquals("unreadable", reply.code)
        assertTrue(folders().isEmpty())
        assertEquals(1, platform.closes)
    }

    @Test
    fun `a source that cannot be closed changes nothing`() {
        platform.content = bytes(50)
        platform.closeFailure = IOException("close failed")

        val reply = pick()

        assertEquals(50L, (reply.value as Map<*, *>)["size"])
    }

    @Test
    fun `name and size that cannot be asked are simply missing`() {
        platform.describeFailure = SecurityException("no")
        platform.content = bytes(20)

        val answer = pick().value as Map<*, *>

        assertEquals("", answer["name"])
        assertEquals(20L, answer["size"])
    }

    @Test
    fun `a folder that cannot be made is storage`() {
        // A FILE stands where the folder of all picks should be.
        root.writeBytes(byteArrayOf(1))

        val reply = pick()

        assertEquals("storage", reply.code)
        assertEquals(0, platform.opens)
        assertTrue(root.isFile)
    }

    @Test
    fun `a background thread that takes no work is failed, and the call is over`() {
        platform.backgroundRefuses = true
        val reply = pick()

        assertEquals("failed", reply.code)
        assertTrue(folders().isEmpty())

        platform.backgroundRefuses = false
        assertNull(pick().code)
    }

    // --- nobody waits ------------------------------------------------------

    @Test
    fun `a document that arrives when nobody waits is not opened and not copied`() {
        // The app was ended while the picker was open and started again:
        // the result comes back, but no Dart call is waiting for it.
        platform.choose(document)

        assertEquals(0, platform.describes)
        assertEquals(0, platform.opens)
        assertFalse(root.exists())
    }

    @Test
    fun `a document that arrives after detach is not opened and nobody is answered`() {
        val reply = call()
        channel.detach()
        platform.choose(document)

        assertEquals(0, platform.opens)
        assertFalse(root.exists())
        assertEquals(0, reply.answers)
    }

    @Test
    fun `a copy that finishes after detach is deleted and nobody is answered`() {
        platform.holdBackground = true
        val reply = call()
        platform.choose(document)
        channel.detach()

        platform.runHeldWork()

        assertEquals(1, platform.opens)
        assertTrue(folders().isEmpty())
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
        assertEquals(1, platform.opens)
        assertEquals(1, folders().size)
    }

    // --- what an answer may say --------------------------------------------

    @Test
    fun `an error is a code with a fixed text and nothing else`() {
        platform.facts = DocumentFacts("secret-name.pitabak", null)
        platform.openFailure = SecurityException("content://secret/address was refused")

        val reply = pick()

        assertEquals("unreadable", reply.code)
        assertEquals("the document could not be read", reply.message)
        assertNull(reply.details)
        for (code in listOf(
            "cancelled", "too_large", "unreadable", "storage",
            "unavailable", "busy", "invalid", "failed", "anything",
        )) {
            val text = PickedDocumentChannel.messageFor(code)
            assertFalse(text.contains("secret"))
            assertFalse(text.contains("content://"))
            assertFalse(text.contains("/"))
        }
    }

    @Test
    fun `the display name is cleaned and cut, never trusted`() {
        val name = { raw: String? -> PickedDocumentChannel.displayNameOf(raw) }

        assertEquals("", name(null))
        assertEquals("", name(""))
        assertEquals("backup.pitabak", name("backup.pitabak"))
        // Control characters go: line breaks, tabs, NUL, escape, DEL.
        assertEquals("ab", name("a\n\r\t\u0000\u001b\u007fb"))
        // Cut at 255.
        assertEquals(255, name("x".repeat(100_000)).length)
        // Not cut through the middle of a two-part character.
        val twoPart = "\uD83D\uDCDA"
        assertEquals("x".repeat(254), name("x".repeat(254) + twoPart))
        assertEquals("x".repeat(253) + twoPart, name("x".repeat(253) + twoPart))
        // Joiners stay: Indic scripts need them.
        assertEquals("\u0915\u094D\u200D\u0937", name("\u0915\u094D\u200D\u0937"))
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

    /** Plays Android: the picker, the other app's document, the threads. */
    private class FakePlatform(private val root: File) : DocumentPickPlatform {
        var registrations = 0
        var pickerOpens = 0
        var pickerExists = true
        var openingThrows = false

        var facts = DocumentFacts("backup.pitabak", null)
        var describeFailure: Exception? = null
        var describes = 0

        var content = ByteArray(100) { 1 }
        var openGivesNothing = false
        var openFailure: Exception? = null
        var readFailureAfterBytes = -1
        var closeFailure: IOException? = null
        var opens = 0
        var closes = 0

        var holdBackground = false
        var holdMain = false
        var backgroundRefuses = false
        private val heldBackground = ArrayDeque<() -> Unit>()
        private val heldMain = ArrayDeque<() -> Unit>()

        private var onResult: ((Uri?) -> Unit)? = null

        /** The picker closes with [document] (null: nothing chosen). */
        fun choose(document: Uri?) = onResult!!.invoke(document)

        /** Runs what was held back: the background work, then the main thread's. */
        fun runHeldWork(main: Boolean = true) {
            while (heldBackground.isNotEmpty()) heldBackground.removeFirst().invoke()
            if (!main) return
            holdMain = false
            while (heldMain.isNotEmpty()) heldMain.removeFirst().invoke()
        }

        override fun registerPicker(onResult: (Uri?) -> Unit): () -> Boolean {
            registrations++
            this.onResult = onResult
            return {
                if (openingThrows) throw IllegalStateException("launcher is gone")
                if (pickerExists) pickerOpens++
                pickerExists
            }
        }

        override fun describe(document: Uri): DocumentFacts {
            describes++
            describeFailure?.let { throw it }
            return facts
        }

        override fun open(document: Uri): InputStream? {
            opens++
            openFailure?.let { throw it }
            if (openGivesNothing) return null
            return Source()
        }

        override fun picksRoot(): File = root

        override fun runInBackground(work: () -> Unit) {
            if (backgroundRefuses) throw java.util.concurrent.RejectedExecutionException()
            if (holdBackground) heldBackground.addLast(work) else work()
        }

        override fun runOnMainThread(work: () -> Unit) {
            if (holdMain) heldMain.addLast(work) else work()
        }

        private inner class Source : InputStream() {
            private val inner = ByteArrayInputStream(content)
            private var served = 0

            override fun read(): Int = throw UnsupportedOperationException()

            override fun read(buffer: ByteArray): Int {
                if (readFailureAfterBytes in 0..served) throw IOException("the other app went away")
                val limit = if (readFailureAfterBytes < 0) {
                    buffer.size
                } else {
                    minOf(buffer.size, readFailureAfterBytes - served)
                }
                val count = inner.read(buffer, 0, limit)
                if (count > 0) served += count
                return count
            }

            override fun close() {
                closes++
                closeFailure?.let { throw it }
            }
        }
    }
}
