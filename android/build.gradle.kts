allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy {
            force("androidx.datastore:datastore:1.1.7")
            force("androidx.datastore:datastore-android:1.1.7")
            force("androidx.datastore:datastore-core:1.1.7")
            force("androidx.datastore:datastore-core-android:1.1.7")
            force("androidx.datastore:datastore-preferences:1.1.7")
            force("androidx.datastore:datastore-preferences-core:1.1.7")
            force("androidx.datastore:datastore-preferences-android:1.1.7")
            force("androidx.datastore:datastore-preferences-core-android:1.1.7")
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
