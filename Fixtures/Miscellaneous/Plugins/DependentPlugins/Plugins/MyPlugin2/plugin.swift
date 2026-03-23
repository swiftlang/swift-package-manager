import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            throw "Target is not a source target, cannot get a file list"
        }
        guard let inputFilePath = sourceTarget.pluginGeneratedSources.first(where: { $0.lastPathComponent == "MyGeneratedFile.swift" }) else {
            throw "Cannot find MyGeneratedFile.swift, files: \(sourceTarget.pluginGeneratedSources), target: \(target)"
        }
        return [
            .buildCommand(
                displayName: "Running MyExecutable2",
                executable: try context.tool(named: "MyExecutable2").url,
                arguments: ["--input-file-path", inputFilePath.path],
                inputFiles: [inputFilePath],
            )
        ]
    }
}

extension String: Error, LocalizedError {
    public var errorDescription: String? {
        self
    }
}
