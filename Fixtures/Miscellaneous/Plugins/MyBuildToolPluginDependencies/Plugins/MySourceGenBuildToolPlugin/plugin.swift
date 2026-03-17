import PackagePlugin
import Foundation

@main
struct MyPlugin: BuildToolPlugin {

    // Create build commands that don't invoke the MySourceGenBuildTool source generator
    // tool directly, but instead invoke a system tool that invokes it indirectly.  We
    // want to test that we still end up with a dependency on not only that tool but also
    // on the library it depends on, even without including an explicit dependency on it.
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Build Tool Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        let inputFiles = target.sourceFiles.filter({ $0.url.pathExtension == "dat" })
        return try inputFiles.map {
            let inputPath = $0.url
            let outputName = inputPath.deletingPathExtension().appendingPathExtension("swift").lastPathComponent
            let outputPath = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \(inputPath.lastPathComponent)",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").url,
                arguments: [
                    inputPath.path,
                    outputPath.path,
                ],
                inputFiles: [
                    inputPath,
                ],
                outputFiles: [
                    outputPath
                ]
            )
        }
    }
}
