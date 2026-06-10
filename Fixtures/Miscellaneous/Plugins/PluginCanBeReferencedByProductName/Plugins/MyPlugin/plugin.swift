import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PackagePlugin.PluginContext, target: PackagePlugin.Target) async throws -> [PackagePlugin.Command] {
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("gen.swift")
        return [
            .buildCommand(displayName: "Generating code",
                          executable: try context.tool(named: "Exec").url,
                          arguments: [output.path],
                          outputFiles: [output])
        ]
    }
}
