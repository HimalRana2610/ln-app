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
// Pin every Android subproject to compileSdk 36.
//
// flutter_secure_storage 11.0.0 hardcodes `compileSdk = 37`, but API 37 is only
// published as `platforms;android-37.0` under Google's new minor-versioned SDK
// scheme. AGP 9.1.0 resolves the target by the old integer hash `android-37`,
// finds no such directory, and fails with:
//
//   Failed to find target with hash string 'android-37' in: C:\Android\Sdk
//
// No integer-named android-37 package exists in any channel, so the platform
// cannot simply be installed. The plugin does not use API 37 symbols, so
// compiling it against 36 is safe. Remove this once AGP understands the
// `android-37.0` layout, or once the plugin lowers its compileSdk.
//
// Set reflectively because the Android extension type is not on this script's
// compile classpath.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        androidExtension.javaClass.methods
            .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
            ?.invoke(androidExtension, 36)
    }
}

// Must stay after the block above: this forces subprojects to evaluate, and an
// afterEvaluate hook cannot be registered on an already-evaluated project.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
