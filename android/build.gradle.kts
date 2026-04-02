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
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            val android = project.extensions.getByName("android")
            
            // 1. Forzar compileSdk a 36 para compatibilidad con AndroidX moderno
            try {
                val method = android.javaClass.getMethod("setCompileSdkVersion", java.lang.Integer.TYPE)
                method.invoke(android, 36)
            } catch (e: Exception) {
                try {
                    val method = android.javaClass.getMethod("setCompileSdk", java.lang.Integer.TYPE)
                    method.invoke(android, 36)
                } catch (e2: Exception) {}
            }

            // 2. Extraer y configurar el namespace dinámicamente desde el AndroidManifest.xml
            try {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val manifestXml = manifestFile.readText()
                    val pattern = java.util.regex.Pattern.compile("package=\"([^\"]+)\"")
                    val matcher = pattern.matcher(manifestXml)
                    if (matcher.find()) {
                        val packageName = matcher.group(1)
                        val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                        setNamespace.invoke(android, packageName)
                    }
                }
            } catch (e: Exception) {
                // Fallback si la extracción falla
                try {
                    val name = if (project.name == "flutter_app_badger") 
                        "fr.g123k.flutterappbadge.flutterappbadger" 
                    else 
                        "com.messeya.fix.${project.name.replace("-", ".")}"
                    
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, name)
                } catch (e2: Exception) {}
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
