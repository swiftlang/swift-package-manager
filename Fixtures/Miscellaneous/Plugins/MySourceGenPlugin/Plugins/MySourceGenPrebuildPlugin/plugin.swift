import PackagePlugin
 
print("Hello from the Prebuild Plugin!")

let outputPaths: [Path] = targetBuildContext.inputFiles.filter{ $0.path.extension == "dat" }.map { file in
    targetBuildContext.pluginWorkDirectory.appending(file.path.stem + ".swift")
}

if !outputPaths.isEmpty {
    commandConstructor.addPrebuildCommand(
        displayName:
            "Running prebuild command for target \(targetBuildContext.targetName)",
        executable:
            Path("/usr/bin/touch"),
        arguments: 
            outputPaths.map{ $0.string },
        outputFilesDirectory:
            targetBuildContext.pluginWorkDirectory
    )
}
