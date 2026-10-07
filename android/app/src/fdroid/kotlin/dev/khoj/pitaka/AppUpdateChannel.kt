package dev.khoj.pitaka

import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * F-DROID FLAVOR ONLY — the inert twin of the play flavor's
 * `AppUpdateChannel` (S36).
 *
 * Why it exists (beginner note): `MainActivity` lives in `src/main` and is
 * shared by both flavors, so it needs SOME class of this name to call. This
 * one registers nothing. Dart's `PlayAppUpdateService` then receives a
 * `MissingPluginException` on its first call and degrades to silence (the
 * fail-safe path it already has for desktop/tests) — and, more importantly,
 * the F-Droid APK links no Google Play Core code at all. The dependency is
 * `playImplementation` only (see `android/app/build.gradle.kts`).
 *
 * Keep the public surface identical to the play flavor's class.
 */
@Suppress("UNUSED_PARAMETER")
class AppUpdateChannel(activity: FragmentActivity) {

    /** No channels are registered in the F-Droid flavor. */
    fun attach(engine: FlutterEngine) {
        // Intentionally empty.
    }

    /** Nothing to release in the F-Droid flavor. */
    fun detach() {
        // Intentionally empty.
    }
}
