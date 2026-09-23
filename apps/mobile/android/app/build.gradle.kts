import java.util.Properties

// ── Release signing ─────────────────────────────────────────────────────────
//
// ⛔ **The signing key IS the update channel.** Android refuses to install an
// update whose signature does not match the installed app, so every build that
// people upgrade between must be signed by the same key, forever. A key that
// changes means an uninstall — and an uninstall takes the platform keystore with
// it: the strap pairing, the Supabase session, the device token, and any samples
// the phone had not pushed yet.
//
// It used to sign releases with the DEBUG key. That key is generated per machine,
// so an APK built by CI could never have updated one built here — the in-app
// updater would have offered a download that the installer then refused, which is
// the worst of both worlds.
//
// Credentials come from `android/key.properties` (gitignored) or, in CI, from the
// environment. Neither is ever committed; `key.properties.example` documents the
// four names and nothing else.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

/// A property from `key.properties`, falling back to the environment for CI.
fun signingValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

val releaseStorePath = signingValue("storeFile", "HEALTHEE_KEYSTORE_PATH")
val hasReleaseSigning = releaseStorePath != null && file(releaseStorePath).exists()

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "codes.afk.healthee"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "codes.afk.healthee"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "healthee"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = signingValue("storePassword", "HEALTHEE_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "HEALTHEE_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "HEALTHEE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        // A debug build is a SEPARATE app (`codes.afk.healthee.debug`, "healthee
        // debug"). It installs beside the owner's release instead of trying to
        // replace it: the release is signed with a key this machine does not hold,
        // so the only way to put a same-id debug build on the phone would be to
        // uninstall the release — which deletes its unsent measurements and keys.
        // The two apps share nothing on the phone. test/core/debug_variant_test.dart.
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["appLabel"] = "healthee debug"
        }
        release {
            // Falls back to the debug key ONLY for a local `flutter run --release`,
            // and says so loudly. It is deliberately not silent: an unsigned-for-
            // release APK that looks identical is exactly what shipped before, and
            // the failure it causes surfaces months later on somebody's phone as a
            // refused update. The release WORKFLOW passes `-PrequireReleaseSigning`
            // and fails outright rather than falling back — see release.yml.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                if (project.hasProperty("requireReleaseSigning")) {
                    throw GradleException(
                        "No release keystore. Expected android/key.properties or " +
                            "HEALTHEE_KEYSTORE_PATH in the environment. A release " +
                            "signed with the debug key cannot update anybody's install."
                    )
                }
                logger.warn(
                    "⚠ Signing the release build with the DEBUG key. This APK can " +
                        "only ever update installs signed by THIS machine's debug " +
                        "key — never publish it."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
