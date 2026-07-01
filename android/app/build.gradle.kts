import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// M6: real release signing. Credentials live in `android/key.properties`
// (git-ignored — NEVER commit the keystore or its passwords). Create it from
// `android/key.properties.example` and point it at a keystore you generate with:
//   keytool -genkey -v -keystore ~/pitak-release.jks -keyalg RSA \
//           -keysize 2048 -validity 10000 -alias pitak
// When the file is absent (e.g. a fresh dev checkout or CI without secrets) the
// build falls back to debug signing so `flutter run --release` still works, but
// a release build that is meant for distribution MUST have key.properties.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.khoj.pitaka"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // F-Droid: AGP 8 embeds a "Dependency metadata" blob in the APK signing
    // block (a Google/Play-oriented, non-reproducible extra block). F-Droid's
    // `check apk` scanner rejects it. Disabling it keeps the APK clean and
    // reproducible; it has no effect on app behaviour.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    defaultConfig {
        // F-Droid distribution identity. This MUST match the package already
        // published on F-Droid (dev.khoj.pitaka.fdroid) so existing users
        // receive pitak-x as an in-place UPDATE rather than a second app.
        // The code/resource package (namespace, above) stays dev.khoj.pitaka;
        // only the installed applicationId carries the .fdroid suffix.
        // If a separate Play/direct channel is ever added, split this into a
        // product flavor instead of changing it here.
        applicationId = "dev.khoj.pitaka.fdroid"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_zxing (zxing-cpp FFI) requires API 23+. The published F-Droid
        // app already ships minSdk 26, so this strands no existing users.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // F-Droid ships one APK per ABI (`flutter build apk --split-per-abi`).
    // Each split needs a DISTINCT, monotonic versionCode or F-Droid rejects the
    // duplicate. We derive it as base*10 + abiRank so the base (pubspec
    // build-number, e.g. 6) maps to 61/62/63. The recipe mirrors this with
    // `VercodeOperation: ['%c * 10 + 1', '%c * 10 + 2', '%c * 10 + 3']`.
    // x86_64 is lowest and arm64 highest so the device picks arm64 when both
    // are offered. Pattern adapted from poppingmoon/aria (F-Droid reference
    // Flutter+Rust app) android/app/build.gradle.kts.
    val abiCodes = mapOf("x86_64" to 1, "armeabi-v7a" to 2, "arm64-v8a" to 3)
    applicationVariants.all {
        outputs.forEach { output ->
            val abiRank = abiCodes[
                (output as ApkVariantOutputImpl)
                    .filters.find { it.filterType == "ABI" }?.identifier
            ]
            if (abiRank != null) {
                output.versionCodeOverride = this.versionCode * 10 + abiRank
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // M6: use the real release keystore when key.properties is present;
            // otherwise fall back to debug signing for local dev only. A
            // distributable build MUST supply key.properties (see top of file).
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties not found — release build " +
                        "is DEBUG-SIGNED. Do not distribute this artifact."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
