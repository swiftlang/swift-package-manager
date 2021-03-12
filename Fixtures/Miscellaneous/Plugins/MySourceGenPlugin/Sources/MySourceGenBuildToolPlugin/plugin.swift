import PackagePlugin
 
print("Hello from the Build Tool Plugin!")

for inputPath in targetBuildContext.otherFiles {
    guard inputPath.suffix == ".dat" else { continue }
    let outputName = inputPath.basename + ".swift"
    let outputPath = targetBuildContext.outputDir.appending(outputName)
    commandConstructor.createCommand(
        displayName:
            "Generating \(outputName) from \(inputPath.filename)",
        executable:
            try targetBuildContext.lookupTool(named: "MySourceGenBuildTool"),
        arguments: [
            "\(inputPath)",
            "\(outputPath)"
        ],
        inputPaths: [
            inputPath,
        ],
        outputPaths: [
            outputPath
        ]
    )
    commandConstructor.addGeneratedOutputFile(path: outputPath)
}
