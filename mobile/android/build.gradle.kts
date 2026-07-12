import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        maven { url = uri("https://raw.githubusercontent.com/LefuHengqi/PPBaseKit-Android/main") }
        google()
        mavenCentral()
    }
}

subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure(LibraryExtension::class.java) {
            compileSdk = 36
        }
    }
    // LeFu SDK pins compileSdk 33; force 36 after evaluation for AAR metadata.
    afterEvaluate {
        extensions.findByType(LibraryExtension::class.java)?.apply {
            compileSdk = 36
        }
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
