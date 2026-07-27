import PackagePlugin

@main
struct SDLAPIGenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let generator = try context.tool(named: "SDLAPIGenerator")
        let include = context.pluginWorkDirectoryURL
        let moduleMap = include.appending(path: "module.moduleMap")
        let headerFile = include.appending(path: "SDL3.h")

        return [
            .buildCommand(
                displayName: "SDL API Generator",
                executable: generator.url,
                arguments: [moduleMap.path, headerFile.path],
                outputFiles: [moduleMap, headerFile]
            ),
        ]
    }
}
