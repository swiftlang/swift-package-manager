import PackagePlugin

for inputPath in targetBuildContext.otherFiles {
    guard inputPath.suffix == ".dat" else { continue }
    let outputName = inputPath.basename + ".swift"
    let outputPath = targetBuildContext.outputDir.appending(outputName)
    commandConstructor.createCommand(
        displayName:
            "Generating \(outputName) from \(inputPath.filename)",
        executable:
            try targetBuildContext.lookupTool(named: "MySourceGenTool"),
        arguments: [
            "\(inputPath)",
            "\(outputPath)"
        ],
        inputPaths: [
            inputPath,
        ],
        outputPaths: [
            outputPath
        ],
        derivedSourcePaths: [
            outputPath
        ]
    )
}
