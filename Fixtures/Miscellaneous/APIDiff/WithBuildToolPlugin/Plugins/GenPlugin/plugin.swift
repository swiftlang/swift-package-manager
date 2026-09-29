import PackagePlugin

@main
struct GenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let out = context.pluginWorkDirectoryURL.appending(path: "Generated.swift")
        return [
            .buildCommand(
                displayName: "Running Gen",
                executable: try context.tool(named: "Gen").url,
                arguments: [out.path()],
                outputFiles: [out],
            ),
        ]
    }
}
