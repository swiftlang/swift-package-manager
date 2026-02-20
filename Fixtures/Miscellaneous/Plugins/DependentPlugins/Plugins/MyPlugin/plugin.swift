import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputFilePath = context.pluginWorkDirectoryURL.appendingPathComponent("MyGeneratedFile.swift")
        return [
            .buildCommand(
                displayName: "Running MyExecutable",
                executable: try context.tool(named: "MyExecutable").url,
                arguments: ["--output-file-path", outputFilePath.path],
                outputFiles: [outputFilePath]
            )
        ]
    }
}
