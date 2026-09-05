allprojects {
    repositories {
        // 国内镜像优先，官方源作为兜底 —— 缺哪个包 Gradle 会自动往后找。
        // 直连 dl.google.com / repo.maven.apache.org 在这里会挂死连接。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
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
// 插件子模块（jni 等）自己声明 `ndkVersion flutter.ndkVersion`，会各自触发
// 下载 28.2.13676358。统一改用本机完整安装的 27.1.12297006。
// 用反射设置是为了不依赖具体 AGP 版本的扩展类型 —— BaseExtension 在 AGP 9 里
// 已经不可用了。
//
// 必须排在下面的 evaluationDependsOn(":app") 之前：那句会强制求值子项目，
// 之后再调 afterEvaluate 会抛 "project is already evaluated"。
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            androidExt.javaClass.methods
                .firstOrNull { it.name == "setNdkVersion" && it.parameterCount == 1 }
                ?.invoke(androidExt, "27.1.12297006")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
