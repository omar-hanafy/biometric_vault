group = "io.github.omarhanafy.biometric_vault"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.13.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Kotlin support comes from Flutter's Built-in Kotlin (Flutter 3.44+), so the
// Kotlin Gradle Plugin must not be applied here:
// https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
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
    implementation("androidx.biometric:biometric:1.4.0-alpha05")
    // core 1.19.x requires AGP 9.1+ / compileSdk 37, which the Flutter
    // toolchain does not support yet; 1.18.0 is the newest consumable version.
    implementation("androidx.core:core:1.18.0")
    implementation("androidx.fragment:fragment:1.8.9")
    testImplementation("junit:junit:4.13.2")
}
