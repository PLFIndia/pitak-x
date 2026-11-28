package dev.khoj.pitaka

import dev.khoj.pitaka.DocumentCopyOut.OpenPlace
import dev.khoj.pitaka.DocumentCopyOut.Outcome
import dev.khoj.pitaka.DocumentCopyOut.Stored
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Stage 8 (review finding P4-M6): which file of the app may leave it, and
 * the copy of that file into the place the user chose.
 *
 * What these tests guard:
 *  - only a finished file in one of the app's two working folders is ever
 *    taken, whatever text comes over the channel;
 *  - a link is never followed out of those folders;
 *  - a copy counts as "copied" only when every byte of the checked file
 *    arrived, the place then SAID that the bytes are stored (D182), and it
 *    closed without an error;
 *  - a place that cannot be asked is never "copied" (D183);
 *  - when the app's own file cannot be opened, the place is never opened.
 */
class DocumentCopyOutTest {
    @get:Rule
    val temp = TemporaryFolder()

    private lateinit var cache: File

    @Before
    fun setUp() {
        cache = File(temp.root, "cache").apply { mkdirs() }
    }

    private fun bytes(count: Int) = ByteArray(count) { (it % 251).toByte() }

    /** Makes `<cache>/<folder>/<run>/<name>` with [size] bytes. */
    private fun fileIn(
        folder: String = "backup_work",
        run: String = "run-Ab3_x-9",
        name: String = "pitak-backup-02Nov2026-134659.pitabak",
        size: Int = 300,
    ): File {
        val dir = File(File(cache, folder), run).apply { mkdirs() }
        return File(dir, name).apply { writeBytes(bytes(size)) }
    }

    private fun check(argument: Any?, maxBytes: Long = DocumentCopyOut.MAX_SOURCE_BYTES) =
        DocumentCopyOut.checkedSource(argument, cache, maxBytes)

    // --- the rule for the path: what is taken ------------------------------

    @Test
    fun `a backup in its run folder is taken, with its name, type and size`() {
        val file = fileIn()

        val source = check(file.path)!!

        assertEquals(file.canonicalFile, source.file)
        assertEquals("pitak-backup-02Nov2026-134659.pitabak", source.name)
        assertEquals("application/octet-stream", source.mimeType)
        assertEquals(300L, source.bytes)
    }

    @Test
    fun `the type follows the ending, by a fixed table of four`() {
        val expected = mapOf(
            "pitak-backup-02Nov2026-134659.pitabak" to "application/octet-stream",
            "pitak-export-20261122.json" to "application/json",
            "pitak-library-20261122.csv" to "text/csv",
            "pitak-donated-ram-sharma-20261122.pdf" to "application/pdf",
        )
        for ((name, type) in expected) {
            val source = check(fileIn(folder = "export_work", name = name).path)

            assertEquals(name, type, source?.mimeType)
            assertEquals(name, source?.name)
        }
        assertEquals(4, DocumentCopyOut.TYPES.size)
    }

    @Test
    fun `both working folders are taken, and no other folder`() {
        assertNotNull(check(fileIn(folder = "backup_work").path))
        assertNotNull(check(fileIn(folder = "export_work").path))

        val others = listOf("picked_documents", "share_plus", "databases", "Backup_work", "backup_work2")
        for (folder in others) {
            assertNull(folder, check(fileIn(folder = folder).path))
        }
    }

    @Test
    fun `the cache folder reached through a link is the same folder`() {
        // On a phone `/data/user/0/<app>` is a link to `/data/data/<app>`:
        // Dart and Kotlin may each spell the cache folder the other way.
        val file = fileIn()
        val link = File(temp.root, "user-0")
        Files.createSymbolicLink(link.toPath(), cache.toPath())

        val source = check(File(link, "backup_work/run-Ab3_x-9/${file.name}").path)

        assertEquals(file.canonicalFile, source?.file)
    }

    // --- the rule for the path: what is refused ----------------------------

    @Test
    fun `anything but a text is refused`() {
        val file = fileIn()
        val notTexts = listOf<Any?>(null, 7, 7L, 1.5, true, listOf(file.path), mapOf("path" to file.path), file)
        for (argument in notTexts) {
            assertNull("$argument", check(argument))
        }
    }

    @Test
    fun `an empty, an endless, a broken or a relative text is refused`() {
        val file = fileIn()

        assertNull(check(""))
        assertNull(check(" "))
        assertNull(check(file.path + "\u0000"))
        assertNull(check("\u0000" + file.path))
        assertNull(check("/" + "a".repeat(DocumentCopyOut.MAX_PATH_CHARS)))
        assertNull(check(file.path.removePrefix("/")))
        assertNull(check("backup_work/run-Ab3_x-9/${file.name}"))
    }

    @Test
    fun `what a text says is read from its last three parts`() {
        assertEquals(
            DocumentCopyOut.Named("export_work", "run-a", "pitak.pdf", "application/pdf"),
            DocumentCopyOut.named("/data/user/0/app/cache/export_work/run-a/pitak.pdf"),
        )
        // A doubled slash in the cache folder's part changes nothing; one
        // among the last three parts leaves a part empty.
        assertNotNull(DocumentCopyOut.named("/cache//export_work/run-a/pitak.pdf"))
        assertNull(DocumentCopyOut.named("/cache/export_work//run-a/pitak.pdf"))
        assertNull(DocumentCopyOut.named("/cache/export_work/run-a/pitak.pdf/"))
        // No part for the cache folder at all.
        assertNull(DocumentCopyOut.named("/export_work/run-a/pitak.pdf"))
    }

    @Test
    fun `a text is refused by itself when it is relative, climbs, holds a NUL or is too long`() {
        // No file is looked at here. On a phone a relative path would be
        // read from `/`, where it could name a real file.
        val tail = "/export_work/run-a/pitak.pdf"

        assertNull(DocumentCopyOut.named("data/user/0/app/cache$tail"))
        assertNull(DocumentCopyOut.named("/data/../data/cache$tail"))
        assertNull(DocumentCopyOut.named("/data/./cache$tail"))
        assertNull(DocumentCopyOut.named("/data\u0000/cache$tail"))

        val longest = "/" + "a".repeat(DocumentCopyOut.MAX_PATH_CHARS - 1 - tail.length) + tail
        assertEquals(DocumentCopyOut.MAX_PATH_CHARS, longest.length)
        assertNotNull(DocumentCopyOut.named(longest))
        assertNull(DocumentCopyOut.named("/a$longest"))
    }

    @Test
    fun `a cache folder that cannot be resolved refuses, and nothing is thrown`() {
        val file = fileIn()
        val broken = object : File(cache.path) {
            override fun getCanonicalFile(): File = throw IOException("no")
        }

        assertNull(DocumentCopyOut.checkedSource(file.path, broken))
    }

    @Test
    fun `a file that is not exactly two folders below the cache folder is refused`() {
        val name = "pitak-export-20261122.json"
        val places = listOf(
            File(cache, name),
            File(cache, "export_work/$name"),
            File(cache, "export_work/run-a/deeper/$name"),
            File(cache, "other/export_work/run-a/$name"),
            File(temp.root, "export_work/run-a/$name"),
        )
        for (place in places) {
            place.parentFile!!.mkdirs()
            place.writeBytes(bytes(10))

            assertNull(place.path, check(place.path))
        }
    }

    @Test
    fun `a run folder must be named as the app names its runs`() {
        val notRuns = listOf(
            "pick-abc", "run-", "run", "run-a.b", "run-a b", "Run-abc", "xrun-abc",
            "run-" + "a".repeat(65),
        )
        for (run in notRuns) {
            assertNull(run, check(fileIn(run = run).path))
        }
        assertNotNull(check(fileIn(run = "run-" + "a".repeat(64)).path))
    }

    @Test
    fun `a file name is plain letters, digits and hyphens with one of four endings`() {
        val bad = listOf(
            "library.db", "notes.txt", "backup", "pitak.PDF", "pitak.pdf.exe", "pitak.tar.pdf",
            "my backup.pitabak", "my_backup.pitabak", ".pdf", "pitak.pdfx", "pitak.pitabak ",
            "\u092A\u093F\u091F\u0915.pdf", "a".repeat(121) + ".pdf",
        )
        for (name in bad) {
            assertNull(name, check(fileIn(name = name).path))
        }
        assertNotNull(check(fileIn(name = "a".repeat(120) + ".pdf").path))
        assertNotNull(check(fileIn(name = "A-9.csv").path))
    }

    @Test
    fun `dots that climb are refused, even when they end at a file that would be taken`() {
        val file = fileIn()
        val run = file.parentFile!!.path

        assertNull(check("$run/../run-Ab3_x-9/${file.name}"))
        assertNull(check("$run/./${file.name}"))
        assertNull(check("${cache.path}/backup_work/../backup_work/run-Ab3_x-9/${file.name}"))
        assertNull(check("${cache.path}/../cache/backup_work/run-Ab3_x-9/${file.name}"))
    }

    @Test
    fun `the catalogue, the vault and a key cannot be named`() {
        // What a mistake on the Dart side must never be able to copy out.
        val secrets = listOf(
            File(temp.root, "databases/pitak.db"),
            File(temp.root, "app_flutter/vault/vault.db"),
            File(temp.root, "shared_prefs/FlutterSecureStorage.xml"),
            File(cache, "picked_documents/pick-abc/document"),
        )
        for (secret in secrets) {
            secret.parentFile!!.mkdirs()
            secret.writeBytes(bytes(50))
            val climbing = "${cache.path}/backup_work/run-a/../../../${secret.relativeTo(temp.root).path}"

            assertNull(secret.path, check(secret.path))
            assertNull(climbing, check(climbing))
        }
    }

    @Test
    fun `a link named like a backup is refused, wherever it points`() {
        val secret = File(temp.root, "databases/pitak.db").apply {
            parentFile!!.mkdirs()
            writeBytes(bytes(50))
        }
        val other = fileIn(folder = "export_work", run = "run-other", name = "pitak-export-20261122.json")
        val run = File(cache, "backup_work/run-links").apply { mkdirs() }

        val toSecret = File(run, "pitak-backup-02Nov2026-134659.pitabak")
        Files.createSymbolicLink(toSecret.toPath(), secret.toPath())
        val toOther = File(run, "pitak-export-20261122.json")
        Files.createSymbolicLink(toOther.toPath(), other.toPath())

        assertNull(check(toSecret.path))
        assertNull(check(toOther.path))
        // The file the second link points at is taken under its own path.
        assertNotNull(check(other.path))
    }

    @Test
    fun `a run folder or a working folder that is a link is refused`() {
        val real = fileIn(run = "run-real")
        val linkedRun = File(cache, "backup_work/run-link")
        Files.createSymbolicLink(linkedRun.toPath(), real.parentFile!!.toPath())

        assertNull(check(File(linkedRun, real.name).path))

        // `export_work` itself is a link to a folder outside the cache folder.
        val outside = File(temp.root, "outside/run-a").apply { mkdirs() }
        File(outside, "pitak-export-20261122.json").writeBytes(bytes(10))
        Files.createSymbolicLink(File(cache, "export_work").toPath(), outside.parentFile!!.toPath())

        assertNull(check(File(cache, "export_work/run-a/pitak-export-20261122.json").path))
    }

    @Test
    fun `a missing file, a folder and an empty file are refused`() {
        val file = fileIn()
        assertNull(check(File(file.parentFile, "pitak-backup-01Nov2026-000000.pitabak").path))

        val folder = File(file.parentFile, "pitak-export-20261122.json").apply { mkdirs() }
        assertNull(check(folder.path))

        assertNull(check(fileIn(name = "pitak-library-20261122.csv", size = 0).path))
    }

    @Test
    fun `exactly the ceiling is taken, one byte more is refused`() {
        val file = fileIn(size = 1000)

        assertEquals(1000L, check(file.path, maxBytes = 1000)?.bytes)
        assertNull(check(file.path, maxBytes = 999))
        // The app's own ceiling is the one the way in has: 2 GiB.
        assertEquals(2L * 1024 * 1024 * 1024, DocumentCopyOut.MAX_SOURCE_BYTES)
        assertEquals(BoundedDocumentCopy.MAX_BYTES_CEILING, DocumentCopyOut.MAX_SOURCE_BYTES)
    }

    // --- the copy ----------------------------------------------------------

    /** How often the place was asked whether the bytes are stored. */
    private var asks = 0

    /**
     * Copies [file] into [place]. When every byte is written the place is
     * asked whether the bytes are stored, and answers [stored].
     */
    private fun copy(
        file: File,
        place: OutputStream?,
        expected: Long = file.length(),
        openSource: ((File) -> InputStream)? = null,
        stored: () -> Stored = { Stored.YES },
    ): Outcome {
        val opened = place?.let {
            OpenPlace(it) {
                asks++
                stored()
            }
        }
        return if (openSource == null) {
            DocumentCopyOut.copy(file, expected, openPlace = { opened })
        } else {
            DocumentCopyOut.copy(file, expected, openPlace = { opened }, openSource = openSource)
        }
    }

    @Test
    fun `a file is copied whole, counted, flushed and closed`() {
        // 64 KiB is one read; this file needs three.
        val file = fileIn(size = 2 * 64 * 1024 + 5)
        val place = Place()

        assertEquals(Outcome.Copied(file.length()), copy(file, place))

        assertArrayEquals(file.readBytes(), place.bytes())
        assertTrue(place.flushes >= 1)
        assertEquals(1, place.closes)
        assertEquals(1, asks)
    }

    // --- D182: the place is asked whether the bytes are stored ---------------

    @Test
    fun `the place is asked after the last byte and the flush, and before the close`() {
        // The look of 2026-11-23: on a full disk every write, the flush and
        // the close succeeded, and the file at the place was a hole. Only a
        // sync, asked while the file is still open, tells.
        val file = fileIn(size = 2 * 64 * 1024 + 5)
        val events = mutableListOf<String>()
        val place = Place(events = events)

        val outcome = copy(file, place, stored = {
            events += "ask"
            Stored.YES
        })

        assertEquals(Outcome.Copied(file.length()), outcome)
        assertEquals(listOf("write", "write", "write", "flush", "ask", "close"), events)
    }

    @Test
    fun `a place that says the bytes are not stored is a failed place, never a copy`() {
        val file = fileIn()
        val place = Place()

        assertEquals(Outcome.PlaceFailed, copy(file, place, stored = { Stored.NO }))

        // Every byte was written and counted, and it is still not a copy.
        assertArrayEquals(file.readBytes(), place.bytes())
        assertEquals(1, asks)
        assertEquals(1, place.closes)
    }

    @Test
    fun `a place that cannot be asked is not a copy either, and has an answer of its own`() {
        val file = fileIn()
        val place = Place()

        assertEquals(
            Outcome.PlaceCannotConfirm,
            copy(file, place, stored = { Stored.CANNOT_TELL }),
        )
        assertEquals(1, place.closes)
    }

    @Test
    fun `a question that throws is a no`() {
        val file = fileIn()
        val place = Place()

        val outcome = copy(file, place, stored = { throw IOException("content://secret") })

        assertEquals(Outcome.PlaceFailed, outcome)
        assertEquals(1, place.closes)
    }

    @Test
    fun `the place is not asked when the copy has failed before`() {
        val file = fileIn(size = 3 * 64 * 1024)
        val failures = listOf<() -> Outcome>(
            { copy(file, Place(failWriteAfter = 64 * 1024L)) },
            { copy(file, Place(flushFails = true)) },
            { copy(file, Place(), expected = file.length() + 1) },
            { copy(file, Place(), expected = 64 * 1024L + 1) },
            { copy(file, Place(), openSource = { Source(bytes(500), failAfter = 200) }) },
        )
        for (failure in failures) {
            asks = 0

            val outcome = failure()

            assertTrue("$outcome", outcome == Outcome.PlaceFailed || outcome == Outcome.SourceFailed)
            assertEquals(0, asks)
        }
    }

    @Test
    fun `a no and a cannot-tell are kept when the close fails too`() {
        val file = fileIn()

        assertEquals(
            Outcome.PlaceFailed,
            copy(file, Place(closeFails = true), stored = { Stored.NO }),
        )
        assertEquals(
            Outcome.PlaceCannotConfirm,
            copy(file, Place(closeFails = true), stored = { Stored.CANNOT_TELL }),
        )
    }

    @Test
    fun `a sync error means cannot-tell only for the errors named, and a no for every other`() {
        // The numbers are made up: the rule is "only what is on the list".
        val noSyncHere = setOf(22, 30)

        assertEquals(Stored.CANNOT_TELL, DocumentCopyOut.storedAfterSyncError(22, noSyncHere))
        assertEquals(Stored.CANNOT_TELL, DocumentCopyOut.storedAfterSyncError(30, noSyncHere))
        // "No space left", "input/output error", and a number nobody knows.
        for (errno in listOf(28, 5, 0, -1, 9999)) {
            assertEquals("errno $errno", Stored.NO, DocumentCopyOut.storedAfterSyncError(errno, noSyncHere))
        }
        // An empty list: every error is a no.
        assertEquals(Stored.NO, DocumentCopyOut.storedAfterSyncError(22, emptySet()))
    }

    @Test
    fun `a place that gives no stream, or cannot be opened, is a failed place`() {
        val file = fileIn()

        assertEquals(Outcome.PlaceFailed, copy(file, null))
        assertEquals(
            Outcome.PlaceFailed,
            DocumentCopyOut.copy(
                file,
                file.length(),
                openPlace = { throw SecurityException("content://secret was refused") },
            ),
        )
    }

    @Test
    fun `when the app's own file cannot be opened the place is never opened`() {
        val file = fileIn()
        val expected = file.length()
        file.delete()
        var placeOpens = 0

        val outcome = DocumentCopyOut.copy(
            file,
            expected,
            openPlace = {
                placeOpens++
                OpenPlace(Place()) { Stored.YES }
            },
        )

        assertEquals(Outcome.SourceFailed, outcome)
        assertEquals(0, placeOpens)
    }

    @Test
    fun `a file that is shorter than it was when it was checked is a failed source`() {
        val file = fileIn(size = 300)
        val place = Place()

        assertEquals(Outcome.SourceFailed, copy(file, place, expected = 301))
        assertEquals(1, place.closes)
    }

    @Test
    fun `a file that grew is a failed source, and never more than was checked is written`() {
        val file = fileIn(size = 3 * 64 * 1024)
        val checked = 64 * 1024L + 1
        val place = Place()

        assertEquals(Outcome.SourceFailed, copy(file, place, expected = checked))

        assertTrue("bytes written: ${place.written}", place.written <= checked)
        assertEquals(1, place.closes)
    }

    @Test
    fun `a source that fails while it is read is a failed source`() {
        val file = fileIn(size = 500)
        val place = Place()
        val source = Source(bytes(500), failAfter = 200)

        assertEquals(Outcome.SourceFailed, copy(file, place, openSource = { source }))

        assertEquals(1, source.closes)
        assertEquals(1, place.closes)
    }

    @Test
    fun `a source that gives nothing and does not end is a failed source`() {
        val file = fileIn()
        val stuck = object : InputStream() {
            override fun read(): Int = throw UnsupportedOperationException()

            override fun read(buffer: ByteArray): Int = 0
        }

        assertEquals(Outcome.SourceFailed, copy(file, Place(), openSource = { stuck }))
    }

    @Test
    fun `a place that fails while it is written is a failed place`() {
        val file = fileIn(size = 3 * 64 * 1024)
        val place = Place(failWriteAfter = 64 * 1024L)

        assertEquals(Outcome.PlaceFailed, copy(file, place))
        assertEquals(1, place.closes)
    }

    @Test
    fun `a flush or a close that fails is a failed place, never a copy`() {
        val file = fileIn()

        assertEquals(Outcome.PlaceFailed, copy(file, Place(flushFails = true)))
        assertEquals(Outcome.PlaceFailed, copy(file, Place(closeFails = true)))
    }

    @Test
    fun `an earlier reason is kept when the close fails too`() {
        val file = fileIn(size = 300)

        assertEquals(Outcome.SourceFailed, copy(file, Place(closeFails = true), expected = 301))
    }

    @Test
    fun `the app's own file is closed on every way out`() {
        val file = fileIn(size = 100)
        val places = listOf<OutputStream?>(
            Place(),
            null,
            Place(failWriteAfter = 0),
            Place(closeFails = true),
        )
        for (place in places) {
            val source = Source(bytes(100))

            copy(file, place, openSource = { source })

            assertEquals(1, source.closes)
        }
    }

    @Test
    fun `a source that cannot be closed does not undo a whole copy`() {
        val file = fileIn(size = 100)
        val source = Source(bytes(100), closeFails = true)

        assertEquals(Outcome.Copied(100), copy(file, Place(), openSource = { source }))
    }

    // --- stand-ins ---------------------------------------------------------

    /** Plays the place the user chose: it keeps what it is given. */
    private class Place(
        private val failWriteAfter: Long = -1,
        private val flushFails: Boolean = false,
        private val closeFails: Boolean = false,
        /** When given, every call is written down here, in its order. */
        private val events: MutableList<String>? = null,
    ) : OutputStream() {
        private val kept = ByteArrayOutputStream()
        var written = 0L
        var flushes = 0
        var closes = 0

        fun bytes(): ByteArray = kept.toByteArray()

        override fun write(oneByte: Int) {
            throw UnsupportedOperationException()
        }

        override fun write(buffer: ByteArray, offset: Int, count: Int) {
            if (failWriteAfter in 0..written) throw IOException("the place went away")
            events?.add("write")
            kept.write(buffer, offset, count)
            written += count
        }

        override fun flush() {
            flushes++
            events?.add("flush")
            if (flushFails) throw IOException("flush failed")
        }

        override fun close() {
            closes++
            events?.add("close")
            if (closeFails) throw IOException("close failed")
        }
    }

    /** Plays the app's own file when it misbehaves. */
    private class Source(
        content: ByteArray,
        private val failAfter: Int = -1,
        private val closeFails: Boolean = false,
    ) : InputStream() {
        private val inner = ByteArrayInputStream(content)
        private var served = 0
        var closes = 0

        override fun read(): Int = throw UnsupportedOperationException()

        override fun read(buffer: ByteArray): Int {
            if (failAfter in 0..served) throw IOException("the file went away")
            val limit = if (failAfter < 0) buffer.size else minOf(buffer.size, failAfter - served)
            val count = inner.read(buffer, 0, limit)
            if (count > 0) served += count
            return count
        }

        override fun close() {
            closes++
            if (closeFails) throw IOException("close failed")
        }
    }
}
