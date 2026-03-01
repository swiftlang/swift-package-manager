import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {
    #if USE_CREATE
    let verb = "Creating"
    #else
    let verb = "Generating"
    #endif

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Build Tool Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        return try target.sourceFiles.map { $0.url }.compactMap { (url: URL) -> Command? in
            guard url.pathExtension == "dat" else { return nil }
            let outputName = url.deletingPathExtension().appendingPathExtension("swift").lastPathComponent
            let outputPath = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            return .buildCommand(
                displayName: "\(verb) \(outputName) from \(url.lastPathComponent)",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").url,
                arguments: [
                    url.path,
                    outputPath.path
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
