import PackagePlugin
 
@main struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: TargetBuildContext) throws -> [Command] {
        var commands: [Command] = []
        for inputFile in context.inputFiles.filter({ $0.path.extension == "dat" }) {
            let inputPath = inputFile.path
            let outputName = "Ambiguous_" + inputPath.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            commands.append(.buildCommand(
                displayName:
                    "This is a constant name",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").path,
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
            ))
        }
        return commands
    }
}
