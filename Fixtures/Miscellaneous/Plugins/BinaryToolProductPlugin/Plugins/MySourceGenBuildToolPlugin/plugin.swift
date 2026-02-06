import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {

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
                    try context.tool(named: "mytool").url,
                arguments: [
                    "--verbose",
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
