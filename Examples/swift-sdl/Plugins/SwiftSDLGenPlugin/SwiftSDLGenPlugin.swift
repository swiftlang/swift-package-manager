import PackagePlugin

@main
struct SwiftSDLGenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let generator = try context.tool(named: "SwiftSDLGenerator")
        let outputFile = context.pluginWorkDirectoryURL.appending(path: "SwiftSDL.swift")

        return [
            .buildCommand(
                displayName: "SDL API Generator",
                executable: generator.url,
                arguments: [outputFile.path],
                outputFiles: [outputFile]
            ),
        ]
    }
}

