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

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://storage.googleapis.com/download.flutter.io")
        }
        maven {
            url = uri("https://gitlab.com/api/v4/projects/37026421/packages/maven")
            credentials(HttpHeaderCredentials::class) {
                name = "Private-Token"
                value = "glpat-FrIzurl1SUvWrJcnhFAa5286MQp1OmRyOXk1Cw.01.120ajowuw"
            }
            authentication {
                create<HttpHeaderAuthentication>("header")
            }
        }
        maven { url = uri("https://jitpack.io") }
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
