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
                arguments: [
                    "--output-dir", "$(BUILD_DIR)",
                    "--products-dir", "$(PRODUCTS_DIR)",
                    "--arches", "$(ARCHES)",
                    "--vendor", "$(VENDOR)",
                    "--os", "$(OS)",
                    "--suffix", "$(SUFFIX)",
                    "--sdk", "$(SDK)",
                    target.directoryURL.path,
                ]
            ),
        ]
    }
}
