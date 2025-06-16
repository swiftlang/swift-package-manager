import Foundation
import PackagePlugin

@main
struct SwiftToolsBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let formatExecutable = context.package.directoryURL.appending(components: "SimpleSwiftScript.swift")
        return [.buildCommand(
            displayName: "Run a swift script",
            executable: formatExecutable,
            arguments: [],
            inputFiles: [formatExecutable],
            outputFiles: []
        )]
    }
}
