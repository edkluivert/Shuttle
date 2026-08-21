pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Held at 8.x, not upgraded to 9. AGP 9 compiles Kotlin itself and refuses
    // any module that applies the Kotlin Gradle Plugin, and this app's plugins
    // disagree about which world they are in: file_picker 11 has migrated and
    // skips KGP on AGP 9, while nsd_android 2.2.0 applies it unconditionally.
    // Neither value of `android.builtInKotlin` satisfies both — off, nothing
    // compiles file_picker's Kotlin; on, nsd_android is rejected outright.
    //
    // Both are already at their latest published versions, so there is nothing
    // to upgrade into. Move back to 9 once nsd ships a build that drops KGP.
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
