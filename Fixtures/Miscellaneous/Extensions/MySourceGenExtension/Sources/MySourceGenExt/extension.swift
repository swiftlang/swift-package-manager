import PackageExtension

for inputPath in targetBuildContext.otherFiles {
    guard inputPath.suffix == ".dat" else { continue }
    let outputName = inputPath.basename + ".swift"
    let outputPath = targetBuildContext.outputDir.appending(outputName)
    commandConstructor.createCommand(
        displayName:
            "MySourceGenTooling \(inputPath)",
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
