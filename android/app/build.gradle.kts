import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}

val signingStoreFilePath = keystoreProperties.getProperty("storeFile")
val signingStorePassword = keystoreProperties.getProperty("storePassword")
val signingKeyAlias = keystoreProperties.getProperty("keyAlias")
val signingKeyPassword = keystoreProperties.getProperty("keyPassword")
val hasReleaseSigning = !signingStoreFilePath.isNullOrBlank() &&
    !signingKeyAlias.isNullOrBlank()

android {
    namespace = "com.rudra.storely"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rudra.storely"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(signingStoreFilePath!!)
                if (signingStoreFilePath.endsWith(".p12")) {
                    storeType = "pkcs12"
                }
                storePassword = signingStorePassword ?: ""
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword ?: ""
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
