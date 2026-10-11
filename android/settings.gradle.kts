// Miroir de Maven Central opéré par Google, utilisable si repo.maven.apache.org limite le débit (erreur HTTP 429).
// Désactivé par défaut. Pour l'activer : ajouter la ligne blurrMavenMirror=true dans ~/.gradle/gradle.properties.
pluginManagement {
    repositories {
        google()
        if (providers.gradleProperty("blurrMavenMirror").orNull == "true") {
            maven("https://maven-central.storage-download.googleapis.com/maven2/")
        }
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        if (providers.gradleProperty("blurrMavenMirror").orNull == "true") {
            maven("https://maven-central.storage-download.googleapis.com/maven2/")
        }
        mavenCentral()
    }
}

rootProject.name = "blurr-android"
include(":app")
