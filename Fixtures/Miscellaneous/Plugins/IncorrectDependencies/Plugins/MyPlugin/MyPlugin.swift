import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        return [.buildCommand(
            displayName: "Running MyPluginExecutable",
            executable: try context.tool(named: "MyPluginExecutable").path,
            arguments: [],
            environment: [:],
            inputFiles: [],
            outputFiles: []
        )]
    }
}
