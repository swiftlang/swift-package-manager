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
            try targetBuildContext.tool(named: "MySourceGenBuildTool").path,
        arguments: [
            "\(inputPath)",
            "\(outputPath)"
        ],
        environment: [
            "VARIABLE_NAME_PREFIX": "PREFIX_"
        ],
        inputFiles: [
            inputPath,
        ],
        outputFiles: [
            outputPath
        ]
    )
}
