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
    // Gradle 9 / AGP 9 removed APIs our plugins still call: video_thumbnail
    // 0.5.6 uses jcenter(), and flutter_inappwebview_android 1.1.3 uses
    // getDefaultProguardFile('proguard-android.txt'). Stay on the AGP 8 line
    // like the sibling repos until those plugins ship Gradle 9 releases.
    id("com.android.application") version "8.12.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.4") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
