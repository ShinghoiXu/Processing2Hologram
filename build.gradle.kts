plugins {
    java
}

group = "io.github.shinghoixu"
version = "0.1.2"

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

repositories {
}

val processingHome = providers.gradleProperty("processingHome")
    .orElse(providers.environmentVariable("PROCESSING_HOME"))
    .orElse(if (System.getProperty("os.name").startsWith("Mac")) {
        "/Applications/Processing.app"
    } else {
        "C:/Program Files/Processing"
    })

val processingApp = if (System.getProperty("os.name").startsWith("Mac")) {
    "${processingHome.get()}/Contents/app"
} else {
    "${processingHome.get()}/app"
}

val processingCore = fileTree("$processingApp/resources/core/library") {
    include("core-*.jar")
}

dependencies {
    compileOnly(processingCore)
    testImplementation(processingCore)
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
}

tasks.register<Exec>("buildProcessingLibrary") {
    if (System.getProperty("os.name").startsWith("Mac")) {
        commandLine("bash", "${projectDir}/build.sh", "--processing-home", processingHome.get())
    } else {
        commandLine(
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", "${projectDir}/build.ps1", "-ProcessingHome", processingHome.get()
        )
    }
}
