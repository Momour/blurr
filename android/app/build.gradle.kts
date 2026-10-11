import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

android {
    namespace = "app.blurr"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.blurr"
        minSdk = 29
        // 34 : évite le mode bord à bord imposé à partir de 35 (interface construite sans gestion des encoches).
        targetSdk = 34
        versionCode = 2
        versionName = "0.2.0"

        // OpenCV pèse lourd : seules les puces 64 bits ARM sont embarquées (tous les téléphones récents).
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // Clé de débogage versionnée avec le projet : les mises à jour s'installent par-dessus
    // quelle que soit la machine de compilation. À remplacer par une vraie clé pour une publication.
    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        noCompress += "onnx"
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    packaging {
        resources.excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1", "META-INF/DEPENDENCIES")
        // Bibliothèques natives compressées dans l'APK (extraites à l'installation) : fichier nettement plus léger à
        // transférer vers le téléphone (OpenCV pèse 24 Mo non compressé).
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    val media3 = "1.11.1"
    implementation("androidx.media3:media3-transformer:$media3")
    implementation("androidx.media3:media3-effect:$media3")
    implementation("androidx.media3:media3-common:$media3")
    implementation("androidx.media3:media3-muxer:$media3")

    // OpenCV (Apache 2.0) : API Java de FaceDetectorYN pour YuNet.
    implementation("org.opencv:opencv:4.14.0")

    implementation("androidx.activity:activity-ktx:1.12.4")
    implementation("androidx.core:core-ktx:1.17.0")

    testImplementation("junit:junit:4.13.2")
}
