import PackagePlugin
 
print("Hello from the Build Tool Plugin!")

for inputPath in targetBuildContext.inputFiles.map{ $0.path } {
    guard inputPath.extension == "dat" else { continue }
    let outputName = inputPath.stem + ".swift"
    let outputPath = targetBuildContext.pluginWorkDirectory.appending(outputName)
    commandConstructor.addBuildCommand(
        displayName:
            "Generating \(outputName) from \(inputPath.lastComponent)",
        executable:
            try targetBuildContext.tool(named: "MySourceGenBuildTool").path,
        arguments: [
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
