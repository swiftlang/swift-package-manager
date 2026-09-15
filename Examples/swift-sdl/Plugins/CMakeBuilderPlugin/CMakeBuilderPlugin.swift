import PackagePlugin
import Foundation

@main
struct CMakeBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let builder = try context.tool(named: "CMakeBuilder")

        let buildDir = context.pluginWorkDirectoryURL.appending(path: "$(BUILD_SUBDIR)")
        let libSDL3 = buildDir.appending(path: "libSDL3.a")
        let productsDir = URL(string: "file:/$(PRODUCTS_DIR)")!

        return [
            .buildCommand(
                displayName: "CMake Build",
                executable: builder.url,
                arguments: [
                    "--output-dir", buildDir.path,
                    "--products-dir", "$(PRODUCTS_DIR)",
                    "--sdk", "$(SDK)",
                    "--triple", "$(TRIPLE)",
                    target.directoryURL.path,
                ],
                outputFiles: [libSDL3]
            ),
            .buildCommand(
                displayName: "Copy libSDL.a",
                executable: URL(string: "file:/$(COPY_CMD)")!,
                arguments: [
                    buildDir.appending(path: "libSDL3.a").path,
                    productsDir.path,
                ],
                inputFiles: [libSDL3],
                outputFiles: [productsDir.appending(path: "libSDL3.a")]
            )
        ]
    }
}
