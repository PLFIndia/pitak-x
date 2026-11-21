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
 * Review finding P4-M8, decision D131: the channel that opens Pitak's own
 * page of the phone's settings. Android is played by [FakePlatform].
 *
 * What these tests guard:
 *  - the page that is asked for is Android's "details of one application",
 *    for the app's OWN package, in the words of the Android reference;
 *  - nothing Dart sends is looked at: Dart cannot choose another page or
 *    another app;
 *  - "no such page on this phone" and every failure are a plain `false`,
 *    never an error and never a text.
 */
class AppSettingsChannelTest {
    private lateinit var platform: FakePlatform
    private lateinit var channel: AppSettingsChannel

    @Before
    fun setUp() {
        platform = FakePlatform()
        channel = AppSettingsChannel(platform)
    }

    private fun open(arguments: Any? = null): Reply {
        val reply = Reply()
        channel.onMethodCall(MethodCall("open", arguments), reply)
        return reply
    }

    @Test
    fun `open asks for the details page of the app's own package`() {
        platform.ownPackage = "dev.khoj.pitaka.fdroid"

        val reply = open()

        // The value of `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`, and
        // its input as the Android reference gives it: "The Intent's data
        // URI specifies the application package name to be shown, with the
        // "package" scheme. That is "package:com.my.app"."
        assertEquals(
            listOf(
                Started(
                    action = "android.settings.APPLICATION_DETAILS_SETTINGS",
                    data = "package:dev.khoj.pitaka.fdroid",
                ),
            ),
            platform.started,
        )
        assertEquals(1, reply.answers)
        assertEquals(true, reply.value)
        assertNull(reply.code)
    }

    @Test
    fun `whatever Dart sends is not looked at`() {
        platform.ownPackage = "dev.khoj.pitaka"
        val sent = listOf<Any?>(
            null,
            "com.other.app",
            "package:com.android.settings",
            mapOf("package" to "com.other.app"),
            mapOf("action" to "android.settings.SETTINGS"),
            listOf("android.intent.action.VIEW", "https://example.com"),
            42,
        )

        for (arguments in sent) {
            val reply = open(arguments)

            assertEquals("arguments $arguments", true, reply.value)
        }
        // Every start asked for the same page of the same app.
        assertEquals(sent.size, platform.started.size)
        assertEquals(
            setOf(
                Started(
                    action = "android.settings.APPLICATION_DETAILS_SETTINGS",
                    data = "package:dev.khoj.pitaka",
                ),
            ),
            platform.started.toSet(),
        )
    }

    @Test
    fun `a phone without such a page answers false, not an error`() {
        platform.noSuchPage = true

        val reply = open()

        assertEquals(1, reply.answers)
        assertEquals(false, reply.value)
        assertNull(reply.code)
        assertFalse(reply.notImplemented)
    }

    @Test
    fun `a start that throws answers false and passes no text on`() {
        platform.startFailure = SecurityException("secret detail of the phone")

        val reply = open()

        assertEquals(1, reply.answers)
        assertEquals(false, reply.value)
        assertNull(reply.code)
        assertNull(reply.message)
    }

    @Test
    fun `an own package name that cannot be read starts nothing`() {
        platform.nameFailure = IllegalStateException("no context yet")

        val reply = open()

        assertEquals(1, reply.answers)
        assertEquals(false, reply.value)
        assertNull(reply.code)
        assertTrue(platform.started.isEmpty())
    }

    @Test
    fun `an unknown method is not implemented and starts nothing`() {
        val reply = Reply()
        channel.onMethodCall(MethodCall("openPage", "android.settings.SETTINGS"), reply)

        assertTrue(reply.notImplemented)
        assertTrue(platform.started.isEmpty())
    }

    /** One start the channel asked Android for. */
    private data class Started(val action: String, val data: String)

    /** Records what the channel answers. */
    private class Reply : MethodChannel.Result {
        var answers = 0
        var value: Any? = null
        var code: String? = null
        var message: String? = null
        var notImplemented = false

        override fun success(result: Any?) {
            answers++
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            answers++
            code = errorCode
            message = errorMessage
        }

        override fun notImplemented() {
            answers++
            notImplemented = true
        }
    }

    /** Plays Android: the app's package name, and the start of a page. */
    private class FakePlatform : AppSettingsPlatform {
        var ownPackage = "dev.khoj.pitaka"
        var noSuchPage = false
        var startFailure: Exception? = null
        var nameFailure: Exception? = null
        val started = ArrayList<Started>()

        override fun ownPackageName(): String {
            nameFailure?.let { throw it }
            return ownPackage
        }

        override fun startPage(action: String, data: String): Boolean {
            startFailure?.let { throw it }
            if (noSuchPage) return false
            started.add(Started(action, data))
            return true
        }
    }
}
