plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fiammettainfernali.umbrareader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications schedules the reading reminders with
        // java.time, which only exists in the platform from API 34. Without
        // desugaring, the AAR metadata check refuses the build outright —
        // it does not wait for a device old enough to break on it.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Matches the iOS bundle id exactly. The Dart package is
        // `umbra_reader`, so `flutter create` derived
        // `com.fiammettainfernali.umbra_reader` — but iOS has shipped as
        // `com.fiammettainfernali.umbrareader` since the first build, and an
        // app that is one identity on one store and another elsewhere is a
        // problem for every service keyed on it later.
        applicationId = "com.fiammettainfernali.umbrareader"
        // minSdk 26 is what the plugin set needs, not a guess:
        // flutter_local_notifications and background_downloader both
        // require 26+, and drift's SQLite bundle is happier there.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys for now, so `flutter run --release` works while this
            // is sideloaded onto one device. A real upload keystore is Phase 3
            // (see docs/ANDROID_PORT_PLAN.md) and must land before Play.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
