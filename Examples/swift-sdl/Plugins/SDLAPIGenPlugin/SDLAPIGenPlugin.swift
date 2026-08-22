import PackagePlugin

@main
struct SDLAPIGenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let generator = try context.tool(named: "SDLAPIGenerator")
        let include = context.pluginWorkDirectoryURL
        let moduleMap = include.appending(path: "module.modulemap")
        let headerFile = include.appending(path: "CSDL.h")

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
