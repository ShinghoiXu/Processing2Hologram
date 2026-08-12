plugins {
    java
}

group = "io.github.shinghoixu"
version = "0.1.1"

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

repositories {
}

val processingHome = providers.gradleProperty("processingHome")
    .orElse(providers.environmentVariable("PROCESSING_HOME"))
    .orElse("C:/Program Files/Processing")

val processingCore = fileTree("${processingHome.get()}/app/resources/core/library") {
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
    commandLine(
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "${projectDir}/build.ps1", "-ProcessingHome", processingHome.get()
    )
}
