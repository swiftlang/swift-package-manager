import PackagePlugin

@main
struct CMakeBuilderPlugin: ExternalBuilderPlugin {
    func createExternalBuildCommand(
        context: PluginContext
    ) async throws -> ExternalBuildCommand {
        let builder = try context.tool(named: "CMakeBuilder")

        return .init(
            displayName: "CMake Build",
            executable: builder.url,
            arguments: [context.pluginWorkDirectoryURL.path]
        )
    }
}
