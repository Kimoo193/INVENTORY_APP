import java.util.Properties
import java.io.FileInputStream

// ✅ قراءة key.properties
val keyPropertiesFile = file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.Kammr3.inventory_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion
    buildToolsVersion = "36.0.0"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.Kammr3.inventory_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ إعداد التوقيع بالـ Keystore
    signingConfigs {
        create("release") {
            keyAlias     = keyProperties["keyAlias"]     as String
            keyPassword  = keyProperties["keyPassword"]  as String
            storeFile    = file(keyProperties["storeFile"] as String)
            storePassword= keyProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // ✅ التوقيع بالـ keystore بدل debug
            signingConfig = signingConfigs.getByName("release")

            // ✅ تصغير وإزالة الكود غير المستخدم
            isMinifyEnabled = true

            // ✅ تصغير الـ resources (صور وملفات غير مستخدمة)
            isShrinkResources = true

            // ✅ ProGuard rules
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
}