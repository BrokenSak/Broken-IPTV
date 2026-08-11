import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.brokeniptv.broken_iptv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.brokeniptv.broken_iptv"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Due canali = due APPLICAZIONI diverse, non la stessa con un interruttore
    // dentro: solo così la copia di prova si installa ACCANTO a quella vera
    // invece di sostituirla, con dati, codice del dispositivo e icona suoi.
    //
    // ⚠️ `app_name` NON sta in strings.xml: se ci fosse, il resValue del
    // flavor sarebbe un duplicato e la build fallirebbe. Lo definiscono i
    // flavor, tutti e due.
    // AGP recente: i resValue sono spenti di default e vanno riaccesi, o la
    // build muore con "contains custom resource values, but the feature is
    // disabled".
    buildFeatures {
        resValues = true
    }

    flavorDimensions += "canale"
    productFlavors {
        create("stabile") {
            dimension = "canale"
            resValue("string", "app_name", "Broken IPTV")
        }
        create("prova") {
            dimension = "canale"
            applicationIdSuffix = ".prova"
            versionNameSuffix = "-prova"
            resValue("string", "app_name", "Broken IPTV Prova")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
            // v2 + v3 only (NO v1/JAR): minSdk is 24 (Android 7.0), where v2 is
            // supported everywhere, so v1 is unnecessary — and v1 (JAR) signing
            // is what the Janus exploit (CVE-2017-13156) abuses on Android 7.x.
            // Dropping it closes that hole; a modern installer verifies v2/v3.
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
