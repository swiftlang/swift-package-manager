import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: TargetBuildContext) throws -> [Command] {
        print("Hello from the Build Tool Plugin!")

        let inputFiles = context.inputFiles.filter({ $0.path.extension == "dat" })
        return try inputFiles.map {
            let inputFile = $0
            let inputPath = inputFile.path
            let outputName = inputPath.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \(inputPath.lastComponent)",
                executable:
                    try context.tool(named: "mytool").path,
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
    }
}
