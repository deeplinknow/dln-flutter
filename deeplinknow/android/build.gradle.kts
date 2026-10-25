group = "com.deeplinknow.flutter"
version = "1.4.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// FLT-21: one build file for every supported Flutter version. AGP 9 (Flutter 3.47+ templates)
// compiles Kotlin itself, and applying the Kotlin Android plugin there is an error. AGP 8
// (Flutter 3.24-3.3x apps) needs it, and older Flutter tooling doesn't apply it for plugins.
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
if (agpMajor < 9 && !pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "com.deeplinknow.flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// Configured on the compile tasks, not the `kotlin {}` extension: that accessor only exists when
// the Kotlin plugin is applied in `plugins {}`, and the tasks' compilerOptions work from KGP 1.8.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    // The native SDK does all deferred-link work (FLT-01). Keep in step with SDK-84 (FLT-03).
    implementation("com.deeplinknow:dln-android:1.4.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.14.2")
}
