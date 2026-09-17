import PackagePlugin
import Foundation

@main
struct ApkBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard let sourceTarget = target.sourceModule else {
            return []
        }

        let builder = try context.tool(named: "ApkBuilder")

        let outputDir = context.pluginWorkDirectoryURL.appending(path: "$(BUILD_SUBDIR)")

        let javaFiles = sourceTarget.sourceFiles(withSuffix: ".java").map { $0.url }
        let manifestFile = sourceTarget.sourceFiles.first(where: { $0.url.lastPathComponent == "AndroidManifest.xml"})!

        // TODO: Be more generic on how we find these dependencies
        let productsDir = URL(string: "file:/$(PRODUCTS_DIR)")!
        let sdljar = productsDir.appending(path: "SDL3.jar")
        let native = productsDir.appending(path: "libAndroidExample.so")
        let apk = outputDir.appending(path: "AndroidApp.apk")

        return [
            .buildCommand(
                displayName: "Building apk",
                executable: builder.url,
                arguments: [
                    "--name", target.name,
                    "--output-dir", outputDir.path,
                    "--swift-resource-dir", "$(SWIFT_RESOURCE_DIR)",
                    "--sysroot", "$(SDK)",
                    "--native-lib", native.path,
                    "--jar", sdljar.path,
                    "--manifest", manifestFile.url.path
                ] + javaFiles.flatMap { ["--java", $0.path] },
                inputFiles: [
                    sdljar,
                    native,
                ],
                alwaysOutOfDate: true
            ),
            .buildCommand(
                displayName: "Copy AndroidApp.apk",
                executable: URL(string: "file:/$(COPY_CMD)")!,
                arguments: [
                    apk.path,
                    productsDir.path,
                ],
                inputFiles: [apk],
                outputFiles: [productsDir.appending(path: apk.lastPathComponent)]
            ),
        ]
    }
}