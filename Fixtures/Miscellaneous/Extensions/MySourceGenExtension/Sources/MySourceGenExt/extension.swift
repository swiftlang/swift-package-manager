import PackageExtension


for inputPath in targetBuildContext.otherFiles {
    guard inputPath.hasSuffix(".dat") else { continue }
    
    let outputPath = targetBuildContext.outputDir.appending(inputPath.basename + ".swift")
    print("inputPath:  \(inputPath)")
    print("outputPath: \(outputPath)")

    commandConstructor.createCommand(
        displayName:
            "MySourceGenTooling \(outputPath.string)",
        executable:
            try targetBuildContext.lookupTool(named: "MySourceGenTool"),
        arguments: [
            inputPath.string,
            outputPath.string
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
