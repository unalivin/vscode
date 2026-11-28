import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// The GitHub OAuth client ID is per-machine configuration, never a repo secret: it comes
// from the ignored local.properties or from the environment in CI. An empty value keeps
// the debug build working and makes the Accounts sign-in report "not configured".
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val githubOAuthClientId: String =
    (localProperties.getProperty("github.oauth.clientId")
        ?: System.getenv("GITHUB_OAUTH_CLIENT_ID")
        ?: "").trim()

// Release signing is fully environment driven; the keystore itself is never committed.
val keystorePath: String? = System.getenv("KODRA_KEYSTORE")?.takeIf { it.isNotBlank() }
val keystorePassword: String? = System.getenv("KODRA_KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
val keyAlias: String? = System.getenv("KODRA_KEY_ALIAS")?.takeIf { it.isNotBlank() }
val keyPassword: String? = System.getenv("KODRA_KEY_PASSWORD")?.takeIf { it.isNotBlank() }
val missingSigning = buildList {
    if (keystorePath == null) add("KODRA_KEYSTORE")
    if (keystorePassword == null) add("KODRA_KEYSTORE_PASSWORD")
    if (keyAlias == null) add("KODRA_KEY_ALIAS")
    if (keyPassword == null) add("KODRA_KEY_PASSWORD")
}

android {
    namespace = "dev.sonixdevs.kodra"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.sonixdevs.kodra"
        minSdk = 21
        // Owner decision: targetSdk 28, distribute via GitHub Releases (not Play Store).
        // compileSdk is 35 to get modern WebView/WindowInsets APIs; target remains 28.
        targetSdk = 28
        // Release builds derive both values from the tag so versions stay monotonic.
        versionCode = (findProperty("kodraVersionCode") as String?)?.toInt() ?: 1
        versionName = (findProperty("kodraVersionName") as String?) ?: "0.3.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }

        buildConfigField("String", "GITHUB_OAUTH_CLIENT_ID", "\"$githubOAuthClientId\"")
    }

    signingConfigs {
        if (missingSigning.isEmpty()) {
            create("release") {
                storeFile = File(keystorePath!!)
                storePassword = keystorePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (missingSigning.isEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
            buildConfigField("boolean", "ENABLE_WEBVIEW_DEBUGGING", "false")
        }
        getByName("debug") {
            isDebuggable = true
            // WebView debugging only in debug (chrome://inspect)
            buildConfigField("boolean", "ENABLE_WEBVIEW_DEBUGGING", "true")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures { buildConfig = true }

    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }

    lint {
        abortOnError = false
        warningsAsErrors = false
        disable += setOf("MissingTranslation", "ExtraTranslation")
    }

    // Keep 16 KB page-size ready (Android 15) — NDK r26+ already supports it.
    // ndkVersion = "26.1.10909125"
}

// A release APK that ships unsigned is not installable, so a release build without a
// keystore must fail here rather than produce an artifact nobody can use. Debug builds
// are unaffected (they sign with the debug keystore).
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { it.name.contains("Release") }
    if (!releaseRequested) return@whenReady
    if (missingSigning.isNotEmpty()) {
        throw GradleException(
            "Release build requires signing credentials; missing: ${missingSigning.joinToString()}. " +
                "Provide them as environment variables (see kodra/RELEASE.md)."
        )
    }
    val keystore = File(keystorePath!!)
    if (!keystore.isFile) {
        throw GradleException("KODRA_KEYSTORE points at '${keystore.absolutePath}', which is not a readable file.")
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.activity:activity-ktx:1.8.2")
    implementation("androidx.lifecycle:lifecycle-service:2.7.0")
    // lifecycleScope comes from the -ktx artifact; appcompat only pulls the plain runtime.
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.webkit:webkit:1.9.0")
    implementation("com.google.android.material:material:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:runner:1.5.2")
}
