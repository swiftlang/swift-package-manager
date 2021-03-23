import PackagePlugin
 
print("Hello from the Build Tool Plugin!")

for inputPath in targetBuildContext.otherFiles {
    guard inputPath.suffix == ".dat" else { continue }
    let outputName = inputPath.basename + ".swift"
    let outputPath = targetBuildContext.outputDir.appending(outputName)
    commandConstructor.createBuildCommand(
        displayName:
            "Generating \(outputName) from \(inputPath.filename)",
        executable:
            try targetBuildContext.tool(named: "mytool").path,
        arguments: [
            "--verbose",
            "\(inputPath)",
            "\(outputPath)"
        ],
        inputFiles: [
            inputPath,
        ],
        outputFiles: [
            outputPath
        ]
    )
}
