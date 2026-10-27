import PackagePlugin

@main
struct SwiftSDLGenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let generator = try context.tool(named: "SwiftSDLGenerator")
        return [
            .buildCommand(
                displayName: "SDL API Generator",
                executable: generator.url,
                arguments: []
            )
        ]
    }
}
