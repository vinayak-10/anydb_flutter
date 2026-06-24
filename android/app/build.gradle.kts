import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.anydb_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Load keystore properties from key.properties file safely
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { input ->
            keystoreProperties.load(input)
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // COMPATIBILITY FIX: Using the universally supported string assignment 
    // to bypass Kotlin version mismatch errors on the compiler options DSL
    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            // Defensive validation check: If key.properties loaded values, apply them strictly
            if (!keystoreProperties.isEmpty) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                
                val storePath = keystoreProperties.getProperty("storeFile")
                if (!storePath.isNullOrEmpty()) {
                    storeFile = file(storePath)
                }
                
                // Explicitly enforce modern cryptographic signature blocks required by Android 11+
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            } else {
                // Fallback debug parameters if key.properties configuration isn't supplied
                logger.warn("WARNING: key.properties is empty or missing! App will sign with debug keys.")
                keyAlias = "androiddebugkey"
                keyPassword = "android"
                storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
                storePassword = "android"
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.anydb_flutter"
        
        // Explicitly declare safe baselines to resolve any internal manifest merge conflicts
        minSdk = 24 // Enforces Android 7.0 Nougat as the absolute minimum baseline
        targetSdk = 34
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Apply the strictly validated release configuration verified above
            signingConfig = signingConfigs.getByName("release")
            
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
