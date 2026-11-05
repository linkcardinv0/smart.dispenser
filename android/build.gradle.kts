plugins {
    id("com.google.gms.google-services") version "4.4.1" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Menyelaraskan keserasian Java & Kotlin ke versi 17 untuk semua sub-projek
subprojects {
    plugins.withId("com.android.application") { configureJavaCompatibility(this@subprojects) }
    plugins.withId("com.android.library") { configureJavaCompatibility(this@subprojects) }

    // Setkan sasaran Kotlin JVM ke 17 secara seragam
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

fun configureJavaCompatibility(project: Project) {
    val androidExtension = project.extensions.findByName("android") ?: return
    try {
        val compileOptions = androidExtension.javaClass.getMethod("getCompileOptions").invoke(androidExtension)
        compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
        compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
    } catch (_: Exception) {
        // Abaikan jika struktur plugin berbeza
    }
}