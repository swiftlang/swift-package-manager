import PackagePlugin
 
for inputFile in targetBuildContext.inputFiles.filter({ $0.path.extension == "dat" }) {
    let inputPath = inputFile.path
    let outputName = "Ambiguous_" + inputPath.stem + ".swift"
    let outputPath = targetBuildContext.pluginWorkDirectory.appending(outputName)
    commandConstructor.addBuildCommand(
        displayName:
            "This is a constant name",
        executable:
            try targetBuildContext.tool(named: "MySourceGenBuildTool").path,
        arguments: [
            "\(inputPath)",
            "\(outputPath)"
        ],
        environment: [
            "VARIABLE_NAME_PREFIX": "SECOND_PREFIX_"
        ],
        inputFiles: [
            inputPath,
        ],
        outputFiles: [
            outputPath
        ]
    )
}
