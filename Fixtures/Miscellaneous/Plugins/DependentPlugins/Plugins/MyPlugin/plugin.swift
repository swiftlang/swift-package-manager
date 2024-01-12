import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputFilePath = context.pluginWorkDirectory.appending("MyGeneratedFile.swift")        
        return [
            .buildCommand(
                displayName: "Running MyExecutable",
                executable: try context.tool(named: "MyExecutable").path,
                arguments: ["--output-file-path", outputFilePath.string],
                outputFiles: [outputFilePath]
            )
        ]
    }
}
