group = "io.github.omarhanafy.biometric_vault"
version = "1.0-SNAPSHOT"

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Kotlin support comes from Flutter's Built-in Kotlin (Flutter 3.44+), so the
// Kotlin Gradle Plugin must not be applied here:
// https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
// Resolve AGP/Kotlin from the consuming Flutter app so the library does not
// force newer Gradle or Kotlin versions than that app supports.
plugins {
    id("com.android.library")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

android {
    namespace = "io.github.omarhanafy.biometric_vault"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("proguard.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        disable += "InvalidPackage"
    }
}

dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    // core 1.19.x requires compileSdk 37; use the latest release compatible
    // with Flutter's supported compileSdk 36.
    implementation("androidx.core:core:1.18.0")
    implementation("androidx.fragment:fragment:1.9.1")
    testImplementation("junit:junit:4.13.2")
}
