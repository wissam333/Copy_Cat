// NOTE: mirror-first repositories. On this machine dl.google.com's maven
// downloads return 404 for everything (maven paths served 404s by the
// local network), so Google/Maven Central are reached through regional
// mirrors first. Huawei is primary (stable, on-demand proxy of google +
// central), Aliyun secondary (it had an outage window during setup).
// Official repos stay last as fallback.
allprojects {
    repositories {
        maven("https://repo.huaweicloud.com/repository/maven/")
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        // Flutter engine artifacts (io.flutter) — CN official storage.
        maven("https://storage.flutter-io.cn/download.flutter.io")
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
