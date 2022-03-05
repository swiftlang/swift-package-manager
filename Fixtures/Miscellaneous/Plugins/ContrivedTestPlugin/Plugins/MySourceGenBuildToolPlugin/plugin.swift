import PackagePlugin
 
@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let inputFiles = target.sourceFiles.filter({ $0.path.extension == "dat" })
        return try inputFiles.map {
            let inputFile = $0
            let inputPath = inputFile.path
            let outputName = inputPath.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \(inputPath.lastComponent)",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").path,
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
    }
}
