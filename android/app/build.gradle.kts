import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.anydb_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Securely resolve and load keystore properties
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

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            // CRITICAL SIGNING PROTECTION: Force absolute validation on the CI runner
            if (!keystoreProperties.isEmpty) {
                val alias = keystoreProperties.getProperty("keyAlias")
                val keyPass = keystoreProperties.getProperty("keyPassword")
                val storePass = keystoreProperties.getProperty("storePassword")
                val storePath = keystoreProperties.getProperty("storeFile")

                if (alias.isNullOrEmpty() || keyPass.isNullOrEmpty() || storePass.isNullOrEmpty() || storePath.isNullOrEmpty()) {
                    throw GradleException("Signing Error: key.properties contains null or empty credentials!")
                }

                // Resolve keystore file relative to the app project module directory
                val keystoreFile = file(storePath)
                if (!keystoreFile.exists()) {
                    throw GradleException("Signing Error: Keystore file not found at path: ${keystoreFile.absolutePath}")
                }

                keyAlias = alias
                keyPassword = keyPass
                storeFile = keystoreFile
                storePassword = storePass

                // Strictly enforce modern signature block tables
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            } else {
                throw GradleException("Signing Error: key.properties file was not found or could not be loaded by Gradle!")
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.anydb_flutter"
        minSdk = 24 // Safe baseline for all modern package parsing parameters
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
