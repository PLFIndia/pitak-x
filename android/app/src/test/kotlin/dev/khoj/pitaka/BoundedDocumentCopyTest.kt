package dev.khoj.pitaka

import dev.khoj.pitaka.BoundedDocumentCopy.Outcome
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.math.BigInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * BR5b: the copy of a picked document counts what really arrives and never
 * lets more than the cap reach the disk. The source is another app's code,
 * so every test here plays a source (or a disk) that misbehaves in one way.
 */
class BoundedDocumentCopyTest {
    @get:Rule
    val temp = TemporaryFolder()

    private fun target() = File(temp.root, "document")

    private fun bytes(count: Int) = ByteArray(count) { (it % 251).toByte() }

    // --- the cap ---------------------------------------------------------

    @Test
    fun `a source of exactly the cap is copied whole`() {
        val data = bytes(1000)
        val outcome = BoundedDocumentCopy.copy(ByteArrayInputStream(data), target(), 1000)

        assertEquals(Outcome.Copied(1000), outcome)
        assertArrayEquals(data, target().readBytes())
    }

    @Test
    fun `one byte over the cap is too large and leaves no file`() {
        val outcome = BoundedDocumentCopy.copy(ByteArrayInputStream(bytes(1001)), target(), 1000)

        assertEquals(Outcome.TooLarge, outcome)
        assertFalse(target().exists())
    }

    @Test
    fun `the cap holds across several reads`() {
        // 64 KiB is one read; this source needs three.
        val size = 2 * 64 * 1024 + 5
        val data = bytes(size)

        assertEquals(
            Outcome.Copied(size.toLong()),
            BoundedDocumentCopy.copy(ByteArrayInputStream(data), target(), size.toLong()),
        )
        assertArrayEquals(data, target().readBytes())

        val second = File(temp.root, "second")
        assertEquals(
            Outcome.TooLarge,
            BoundedDocumentCopy.copy(ByteArrayInputStream(data), second, size.toLong() - 1),
        )
        assertFalse(second.exists())
    }

    @Test
    fun `a source without end stops at the cap and never fills the disk`() {
        val cap = 200_000L
        val file = target()
        val source = EndlessSource(watch = file)

        assertEquals(Outcome.TooLarge, BoundedDocumentCopy.copy(source, file, cap))

        assertFalse(file.exists())
        // The check comes before the write: the file was never above the cap.
        assertTrue("largest file seen: ${source.largestFileSeen}", source.largestFileSeen <= cap)
        // And the source was not read on and on: at most one read past the cap.
        assertTrue("bytes served: ${source.served}", source.served <= cap + 64 * 1024)
    }

    @Test
    fun `never more than the cap is written, not even for a moment`() {
        // The file is deleted after a refusal, so its size cannot be looked
        // at afterwards. This output counts every byte handed to the disk.
        for (source in listOf<InputStream>(ByteArrayInputStream(bytes(1001)), EndlessSource(target()))) {
            var output: CountingOutput? = null

            val outcome = BoundedDocumentCopy.copy(source, target(), 1000) { file ->
                CountingOutput(FileOutputStream(file)).also { output = it }
            }

            assertEquals(Outcome.TooLarge, outcome)
            assertTrue("bytes written: ${output!!.written}", output!!.written <= 1000)
            assertFalse(target().exists())
        }
    }

    @Test
    fun `a cap below one byte allows nothing and creates nothing`() {
        for (cap in longArrayOf(0, -1, Long.MIN_VALUE)) {
            val source = CountingSource(bytes(10))

            assertEquals(Outcome.TooLarge, BoundedDocumentCopy.copy(source, target(), cap))
            assertFalse(target().exists())
            assertEquals(0, source.reads)
        }
    }

    // --- sources that behave oddly -----------------------------------------

    @Test
    fun `a source that gives one byte per read is copied whole`() {
        val data = bytes(300)
        val source = object : InputStream() {
            private var next = 0
            override fun read(): Int = if (next < data.size) data[next++].toInt() and 0xff else -1
            override fun read(buffer: ByteArray): Int {
                if (next >= data.size) return -1
                buffer[0] = data[next++]
                return 1
            }
        }

        assertEquals(Outcome.Copied(300), BoundedDocumentCopy.copy(source, target(), 300))
        assertArrayEquals(data, target().readBytes())
    }

    @Test
    fun `an empty source gives an empty file`() {
        val outcome = BoundedDocumentCopy.copy(ByteArrayInputStream(ByteArray(0)), target(), 10)

        assertEquals(Outcome.Copied(0), outcome)
        assertTrue(target().exists())
        assertEquals(0L, target().length())
    }

    @Test
    fun `a read that fails half-way is unreadable and leaves no file`() {
        val failures = listOf<Exception>(
            IOException("the other app went away"),
            SecurityException("access was taken back"),
            IllegalStateException("anything else"),
        )
        for (failure in failures) {
            val source = FailingSource(bytes(100_000), failAfterBytes = 70_000, failure = failure)

            assertEquals(Outcome.Unreadable, BoundedDocumentCopy.copy(source, target(), 1_000_000))
            assertFalse("after $failure", target().exists())
        }
    }

    // With a time limit: the mistake this guards against is a loop without
    // end, and a test that hangs says less than one that fails.
    @Test(timeout = 10_000)
    fun `a source that gives nothing without ending is unreadable`() {
        val source = object : InputStream() {
            var reads = 0
            override fun read(): Int = -1
            override fun read(buffer: ByteArray): Int {
                reads++
                return 0
            }
        }

        assertEquals(Outcome.Unreadable, BoundedDocumentCopy.copy(source, target(), 10))
        assertFalse(target().exists())
        assertEquals(1, source.reads)
    }

    // --- the target ------------------------------------------------------

    @Test
    fun `an existing file is not replaced, not deleted and nothing is read`() {
        target().writeBytes(byteArrayOf(9, 9, 9))
        val source = CountingSource(bytes(10))

        assertEquals(Outcome.NotSaved, BoundedDocumentCopy.copy(source, target(), 100))

        assertArrayEquals(byteArrayOf(9, 9, 9), target().readBytes())
        assertEquals(0, source.reads)
    }

    @Test
    fun `a target whose folder is missing is not saved`() {
        val nowhere = File(File(temp.root, "missing"), "document")

        val outcome = BoundedDocumentCopy.copy(ByteArrayInputStream(bytes(10)), nowhere, 100)

        assertEquals(Outcome.NotSaved, outcome)
        assertFalse(nowhere.exists())
        assertFalse(nowhere.parentFile!!.exists())
    }

    @Test
    fun `a file that cannot be opened for writing is not saved and is removed`() {
        val outcome = BoundedDocumentCopy.copy(ByteArrayInputStream(bytes(10)), target(), 100) {
            throw IOException("no handle left")
        }

        assertEquals(Outcome.NotSaved, outcome)
        assertFalse(target().exists())
    }

    @Test
    fun `a write that fails is not saved and leaves no file`() {
        // Plays a disk that is full after 100 bytes.
        val outcome = BoundedDocumentCopy.copy(
            ByteArrayInputStream(bytes(300_000)),
            target(),
            1_000_000,
        ) { file -> FailingOutput(FileOutputStream(file), failOnWriteNumber = 2) }

        assertEquals(Outcome.NotSaved, outcome)
        assertFalse(target().exists())
    }

    @Test
    fun `a close that fails is not saved and leaves no file`() {
        val outcome = BoundedDocumentCopy.copy(
            ByteArrayInputStream(bytes(10)),
            target(),
            100,
        ) { file -> FailingOutput(FileOutputStream(file), failOnClose = true) }

        assertEquals(Outcome.NotSaved, outcome)
        assertFalse(target().exists())
    }

    @Test
    fun `an earlier reason is kept when the close fails too`() {
        val outcome = BoundedDocumentCopy.copy(
            ByteArrayInputStream(bytes(1001)),
            target(),
            1000,
        ) { file -> FailingOutput(FileOutputStream(file), failOnClose = true) }

        assertEquals(Outcome.TooLarge, outcome)
        assertFalse(target().exists())
    }

    // --- the cap as an argument --------------------------------------------

    @Test
    fun `the cap argument is a whole number from 1 to the ceiling`() {
        val ceiling = BoundedDocumentCopy.MAX_BYTES_CEILING
        assertEquals(2L * 1024 * 1024 * 1024, ceiling)

        assertEquals(1L, BoundedDocumentCopy.checkedMaxBytes(1))
        assertEquals(1L, BoundedDocumentCopy.checkedMaxBytes(1L))
        assertEquals(Int.MAX_VALUE.toLong(), BoundedDocumentCopy.checkedMaxBytes(Int.MAX_VALUE))
        assertEquals(ceiling, BoundedDocumentCopy.checkedMaxBytes(ceiling))
    }

    @Test
    fun `every other cap argument is refused`() {
        val refused = listOf<Any?>(
            null,
            0,
            0L,
            -1,
            -1L,
            Long.MIN_VALUE,
            BoundedDocumentCopy.MAX_BYTES_CEILING + 1,
            Long.MAX_VALUE,
            "1000",
            1000.0,
            1000.5f,
            1000.toShort(),
            BigInteger.TEN,
            true,
            listOf(1000),
            mapOf("maxBytes" to 1000),
        )
        for (argument in refused) {
            assertNull("argument $argument", BoundedDocumentCopy.checkedMaxBytes(argument))
        }
    }

    // --- stand-ins ---------------------------------------------------------

    /** Serves full buffers for ever and notes how large [watch] ever got. */
    private class EndlessSource(private val watch: File) : InputStream() {
        var served = 0L
        var largestFileSeen = 0L

        override fun read(): Int = 7

        override fun read(buffer: ByteArray): Int {
            largestFileSeen = maxOf(largestFileSeen, watch.length())
            served += buffer.size
            return buffer.size
        }
    }

    /** Counts how often it is read. */
    private class CountingSource(data: ByteArray) : InputStream() {
        private val inner = ByteArrayInputStream(data)
        var reads = 0

        override fun read(): Int {
            reads++
            return inner.read()
        }

        override fun read(buffer: ByteArray): Int {
            reads++
            return inner.read(buffer)
        }
    }

    /** Serves [failAfterBytes] bytes, then throws [failure]. */
    private class FailingSource(
        data: ByteArray,
        private val failAfterBytes: Int,
        private val failure: Exception,
    ) : InputStream() {
        private val inner = ByteArrayInputStream(data)
        private var served = 0

        override fun read(): Int = throw failure

        override fun read(buffer: ByteArray): Int {
            if (served >= failAfterBytes) throw failure
            val count = inner.read(buffer, 0, minOf(buffer.size, failAfterBytes - served))
            served += count
            return count
        }
    }

    /** Passes everything on to [inner] and counts the bytes. */
    private class CountingOutput(private val inner: OutputStream) : OutputStream() {
        var written = 0L

        override fun write(oneByte: Int) {
            written++
            inner.write(oneByte)
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            written += length
            inner.write(buffer, offset, length)
        }

        override fun close() = inner.close()
    }

    /** Writes into [inner] until told to fail. */
    private class FailingOutput(
        private val inner: OutputStream,
        private val failOnWriteNumber: Int = 0,
        private val failOnClose: Boolean = false,
    ) : OutputStream() {
        private var writes = 0

        override fun write(oneByte: Int) = inner.write(oneByte)

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            writes++
            if (writes == failOnWriteNumber) throw IOException("No space left on device")
            inner.write(buffer, offset, length)
        }

        override fun close() {
            inner.close()
            if (failOnClose) throw IOException("close failed")
        }
    }
}
