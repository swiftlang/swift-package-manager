import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputDir = target.directory.appending("generated")
        try FileManager.default.createDirectory(atPath: outputDir.string, withIntermediateDirectories: true)
        return [
            .prebuildCommand(
                displayName: "Creating Foo.swift in the target directory…",
                executable: Path("/bin/bash"),
                arguments: [ "-c", "echo 'let foo = \"\(target.name)\"' > '\(outputDir)/foo.swift'" ],
                outputFilesDirectory: outputDir)
        ]
    }
}
