import PackagePlugin

@main
struct CMakeBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let builder = try context.tool(named: "CMakeBuilder")

        return [
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: [target.directoryURL.path]
            ),
        ]
    }
}
