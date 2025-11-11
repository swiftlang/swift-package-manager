import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputFilePath = context.pluginWorkDirectoryURL.appendingPathComponent("MyGeneratedFile.swift")

        // We are attempting to assemble a prebuild command that relies on an executable that hasn't
        // been built yet. This should result in an error in prebuild.
        let myExecutable = try context.tool(named: "MyExecutable")

        return [
            .prebuildCommand(
                displayName: "Prebuild that runs MyExecutable",
                executable: myExecutable.url,
                arguments: ["--output-file-path", outputFilePath.path],
                outputFilesDirectory: context.pluginWorkDirectoryURL
            )
        ]
    }
}
