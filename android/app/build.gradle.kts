import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing config from android/key.properties if present.
// In CI, this file is created from GitHub Secrets before the build.
// For local dev, a missing file falls back to debug signing.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.llloooggg.letsflutssh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.llloooggg.letsflutssh"
        // Pinned explicitly to Android 9 (Pie / API 28) instead of
        // inheriting `flutter.minSdkVersion` (API 24 at Dart 3.11).
        // API 28 is where BiometricPrompt became a first-class API, so
        // the L3 hardware-vault path drops its FingerprintManager
        // fallback. It is also the boundary where `local_auth_android`
        // stops needing its legacy compat shim — running lower would
        // keep us perpetually on the API-24 floor plugins have already
        // been drifting away from. Android 9 covers ~90% of active
        // devices in 2026; earlier releases are <5% and shrinking.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real-key release signing when android/key.properties is
            // present (CI / production). Local builds opt into the
            // debug-keystore fallback explicitly via
            // `-PallowDebugRelease=true` so `flutter run --release`
            // still works for hot-iteration; without the flag a
            // missing key.properties fails the build instead of
            // silently producing a debug-key APK that real-key updates
            // can never replace (INSTALL_FAILED_UPDATE_INCOMPATIBLE).
            val allowDebugRelease =
                (project.findProperty("allowDebugRelease") as? String)?.toBoolean() == true
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else if (allowDebugRelease) {
                signingConfigs.getByName("debug")
            } else {
                throw GradleException(
                    "Release build requires android/key.properties. " +
                        "Pass -PallowDebugRelease=true to fall back to the " +
                        "debug keystore for local iteration."
                )
            }
            // Keep androidx.biometric classes — without this R8 strips
            // BiometricManager / BiometricPrompt and JNI FindClass fails
            // with "class not found or linkage error" on devices that
            // do have hardware biometrics.
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // QR scanning — CameraX pipeline + ZXing core decoder.
    // All Apache-2.0; not Google Play Services / MLKit.  ZXing core is a
    // pure-Java jar, the CameraX artefacts are AndroidX — both link into
    // the APK and work offline on any Android device.
    val cameraX = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraX")
    implementation("androidx.camera:camera-camera2:$cameraX")
    implementation("androidx.camera:camera-lifecycle:$cameraX")
    implementation("androidx.camera:camera-view:$cameraX")
    implementation("com.google.zxing:core:3.5.3")

    // Hardware-backed L3 vault: BiometricPrompt + Fragment host for
    // its UI. `local_auth` already pulls a compatible version, but
    // pinning it here anchors the transitive API that
    // HardwareVaultPlugin compiles against.
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.fragment:fragment-ktx:1.6.2")

    // System FIDO2 / passkey broker: androidx.credentials drives the
    // platform security-key dialog (USB-host / NFC / BLE / StrongBox
    // passkey). The `play-services-auth` companion lights the
    // Credential Manager runtime up on devices where Play Services
    // backs the API; on GMS-less ROMs the system-level CM runtime
    // ships in-platform from API 34+, and the runtime probe in
    // `Fido2Broker.isAvailable()` honestly reports `false` on
    // earlier OS-less-GMS builds.
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
}
