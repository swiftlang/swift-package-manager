import PackagePlugin
 
print("Hello from the Prebuild Plugin!")

let outputPaths: [Path] = targetBuildContext.otherFiles.filter{ $0.suffix == ".dat" }.map { path in
    targetBuildContext.outputDir.appending(path.basename + ".swift")
}

if !outputPaths.isEmpty {
    commandConstructor.createCommand(
        displayName:
            "Running prebuild command for target \(targetBuildContext.targetName)",
        executable:
            Path("/usr/bin/touch"),
        arguments: 
            outputPaths.map{ $0.string }
    )
}

commandConstructor.addPrebuildOutputDirectory(path: targetBuildContext.outputDir)