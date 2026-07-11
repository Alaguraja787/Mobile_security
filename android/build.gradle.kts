import com.android.build.gradle.BaseExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}


subprojects {

    afterEvaluate {

        if (project.hasProperty("android")) {

            extensions.configure<BaseExtension>("android") {

                compileSdkVersion(36)

            }

        }

    }

}


val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()


rootProject.layout.buildDirectory.value(newBuildDir)


subprojects {

    val newSubprojectBuildDir: Directory =
        newBuildDir.dir(project.name)

    project.layout.buildDirectory.value(
        newSubprojectBuildDir
    )

}


subprojects {

    project.evaluationDependsOn(":app")

}


tasks.register<Delete>("clean") {

    delete(rootProject.layout.buildDirectory)

}