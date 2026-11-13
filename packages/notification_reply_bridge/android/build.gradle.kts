plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "com.farmitra.nearby.reply"
version = "1.0"
android {
    namespace = "com.farmitra.nearby.reply"
    compileSdk = 36
    defaultConfig { minSdk = 21 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }
}
