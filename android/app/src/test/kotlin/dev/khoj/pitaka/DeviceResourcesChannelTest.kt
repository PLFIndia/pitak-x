package dev.khoj.pitaka

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * BR9: the channel that tells Dart how much free storage and available
 * memory the device has. Android is played by [FakePlatform].
 *
 * What these tests guard:
 *  - the figures are passed on as they are, under the agreed keys;
 *  - one figure that cannot be read does not take the other with it;
 *  - nothing Dart sends is looked at, and there is no error answer;
 *  - the read runs in the background and is answered on the main thread;
 *  - nobody is answered once the Flutter side is gone.
 */
class DeviceResourcesChannelTest {
    private lateinit var platform: FakePlatform
    private lateinit var channel: DeviceResourcesChannel

    @Before
    fun setUp() {
        platform = FakePlatform()
        channel = DeviceResourcesChannel(platform)
    }

    private fun read(arguments: Any? = null): Reply {
        val reply = Reply()
        channel.onMethodCall(MethodCall("read", arguments), reply)
        return reply
    }

    @Test
    fun `both figures are passed on under the agreed keys`() {
        platform.freeStorage = 12_345_678_901L
        platform.memoryFacts = MemoryFacts(
            availableBytes = 2_000_000_000L,
            lowThresholdBytes = 300_000_000L,
            lowNow = true,
        )

        val reply = read()

        assertEquals(1, reply.answers)
        assertEquals(
            mapOf(
                "freeStorageBytes" to 12_345_678_901L,
                "availableMemoryBytes" to 2_000_000_000L,
                "lowMemoryThresholdBytes" to 300_000_000L,
                "lowMemory" to true,
            ),
            reply.value,
        )
        assertNull(reply.code)
    }

    @Test
    fun `storage that cannot be read leaves memory in the answer`() {
        platform.storageFailure = IllegalArgumentException("secret path /data/x")

        val reply = read()

        assertEquals(
            setOf("availableMemoryBytes", "lowMemoryThresholdBytes", "lowMemory"),
            reply.keys(),
        )
        assertNull(reply.code)
    }

    @Test
    fun `memory that cannot be read leaves storage in the answer`() {
        platform.memoryFailure = SecurityException("no")

        val reply = read()

        assertEquals(setOf("freeStorageBytes"), reply.keys())
        assertNull(reply.code)
    }

    @Test
    fun `nothing readable is an empty answer, not an error`() {
        platform.storageFailure = IllegalArgumentException("x")
        platform.memoryFailure = IllegalStateException("y")

        val reply = read()

        assertEquals(1, reply.answers)
        assertEquals(emptyMap<String, Any>(), reply.value)
        assertNull(reply.code)
        assertFalse(reply.notImplemented)
    }

    @Test
    fun `whatever Dart sends is not looked at`() {
        val sent = listOf<Any?>(
            null,
            "/data/data/another.app/files",
            mapOf("path" to "/sdcard"),
            listOf(1, 2, 3),
            42,
        )
        for (arguments in sent) {
            val reply = read(arguments)

            assertEquals("arguments $arguments", 4, reply.keys().size)
        }
        // The fake counts every read: one per call, and never with a path.
        assertEquals(sent.size, platform.storageReads)
    }

    @Test
    fun `an unknown method is not implemented and reads nothing`() {
        val reply = Reply()
        channel.onMethodCall(MethodCall("freeBytesOf", "/sdcard"), reply)

        assertTrue(reply.notImplemented)
        assertEquals(0, platform.storageReads)
        assertEquals(0, platform.memoryReads)
    }

    @Test
    fun `the read runs in the background and is answered on the main thread`() {
        platform.hold = true

        val reply = read()

        // Nothing was read on the calling (main) thread.
        assertEquals(0, platform.storageReads)
        assertEquals(0, reply.answers)

        platform.runBackground()
        assertEquals(1, platform.storageReads)
        assertEquals(1, platform.memoryReads)
        // Read, but not yet answered: the answer waits for the main thread.
        assertEquals(0, reply.answers)

        platform.runMain()
        assertEquals(1, reply.answers)
    }

    @Test
    fun `a background thread that cannot start gives an empty answer`() {
        platform.backgroundRefuses = true

        val reply = read()

        assertEquals(1, reply.answers)
        assertEquals(emptyMap<String, Any>(), reply.value)
        assertNull(reply.code)
    }

    @Test
    fun `nobody is answered once the channel is detached`() {
        platform.hold = true
        val reply = read()
        platform.runBackground()

        channel.detach()
        platform.runMain()

        assertEquals(0, reply.answers)
    }

    /** Records what the channel answers. */
    private class Reply : MethodChannel.Result {
        var answers = 0
        var value: Any? = null
        var code: String? = null
        var notImplemented = false

        fun keys(): Set<String> = (value as Map<*, *>).keys.map { it as String }.toSet()

        override fun success(result: Any?) {
            answers++
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            answers++
            code = errorCode
        }

        override fun notImplemented() {
            answers++
            notImplemented = true
        }
    }

    /** Plays Android: the two figures and the two threads. */
    private class FakePlatform : DeviceResourcesPlatform {
        var freeStorage = 5_000_000_000L
        var memoryFacts = MemoryFacts(1_000_000_000L, 200_000_000L, false)
        var storageFailure: Exception? = null
        var memoryFailure: Exception? = null
        var storageReads = 0
        var memoryReads = 0

        /** When true, work is kept until [runBackground] and [runMain]. */
        var hold = false
        var backgroundRefuses = false
        private val heldBackground = ArrayDeque<() -> Unit>()
        private val heldMain = ArrayDeque<() -> Unit>()

        override fun freeStorageBytes(): Long {
            storageReads++
            storageFailure?.let { throw it }
            return freeStorage
        }

        override fun memory(): MemoryFacts {
            memoryReads++
            memoryFailure?.let { throw it }
            return memoryFacts
        }

        override fun runInBackground(work: () -> Unit) {
            if (backgroundRefuses) throw IllegalStateException("no thread")
            if (hold) heldBackground.addLast(work) else work()
        }

        override fun runOnMainThread(work: () -> Unit) {
            if (hold) heldMain.addLast(work) else work()
        }

        fun runBackground() {
            while (heldBackground.isNotEmpty()) heldBackground.removeFirst().invoke()
        }

        fun runMain() {
            while (heldMain.isNotEmpty()) heldMain.removeFirst().invoke()
        }
    }
}
