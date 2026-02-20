import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        var commands: [Command] = []
        for inputFile in target.sourceFiles.filter({ $0.url.pathExtension == "dat" }) {
            let inputPath = inputFile.url
            let outputName = "Ambiguous_" + inputPath.deletingPathExtension().appendingPathExtension("swift").lastPathComponent
            let outputPath = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            commands.append(.buildCommand(
                displayName:
                    "This is a constant name",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").url,
                arguments: [
                    inputPath.path,
                    outputPath.path,
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
