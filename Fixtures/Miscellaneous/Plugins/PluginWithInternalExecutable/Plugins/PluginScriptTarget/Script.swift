import PackagePlugin
import Foundation

@main
struct PluginScript: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the plugin script!")
        guard let target = target as? SourceModuleTarget else { return [] }
        return try target.sourceFiles.map{ $0.url }.compactMap { (url: URL) -> Command? in
            guard url.pathExtension == "dat" else { return nil }
            let outputName = url.deletingPathExtension().appendingPathExtension("swift").lastPathComponent
            let outputPath = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \(url.lastPathComponent)",
                executable:
                    try context.tool(named: "PluginExecutable").url,
                arguments: [
                    url.path,
                    outputPath.path,
                ],
                inputFiles: [
                    url,
                ],
                outputFiles: [
                    outputPath
                ]
            )
        }
    }
}
