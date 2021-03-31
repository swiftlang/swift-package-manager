import PackagePlugin
 
print("Hello from the Build Tool Plugin!")

for inputFile in targetBuildContext.inputFiles.filter({ $0.path.extension == "dat" }) {
    let inputPath = inputFile.path
    let outputName = inputPath.stem + ".swift"
    let outputPath = targetBuildContext.outputDirectory.appending(outputName)
    commandConstructor.createBuildCommand(
        displayName:
            "Generating \(outputName) from \(inputPath.lastComponent)",
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
