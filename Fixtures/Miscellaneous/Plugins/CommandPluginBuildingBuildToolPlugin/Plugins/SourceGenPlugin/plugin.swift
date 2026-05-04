import PackagePlugin
import Foundation

@main
struct SourceGenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        return try target.sourceFiles.compactMap { file -> Command? in
            guard file.url.pathExtension == "dat" else { return nil }
            let outputName = file.url.deletingPathExtension().appendingPathExtension("swift").lastPathComponent
            let outputPath = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            return .buildCommand(
                displayName: "Generating \(outputName) from \(file.url.lastPathComponent)",
                executable: try context.tool(named: "SourceGenTool").url,
                arguments: [file.url.path, outputPath.path],
                inputFiles: [file.url],
                outputFiles: [outputPath]
            )
        }
    }
}
