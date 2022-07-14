import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PackagePlugin.PluginContext, target: PackagePlugin.Target) async throws -> [PackagePlugin.Command] {
        let output = context.pluginWorkDirectory.appending("gen.swift")
        return [
            .buildCommand(displayName: "Generating code",
                          executable: try context.tool(named: "Exec").path,
                          arguments: [output.string],
                          outputFiles: [output])
        ]
    }
}
