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
