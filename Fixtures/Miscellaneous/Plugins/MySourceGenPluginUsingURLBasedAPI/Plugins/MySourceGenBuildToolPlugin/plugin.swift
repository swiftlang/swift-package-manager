import PackagePlugin

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
        return try target.sourceFiles.map{ $0.url }.compactMap {
            guard $0.pathExtension == "dat" else { return .none }
            let outputName = $0.deletingPathExtension().lastPathComponent + ".swift"
            let outputPath = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            return .buildCommand(
                displayName:
                    "\(verb) \(outputName) from \($0.lastPathComponent)",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").url,
                arguments: [
                    "\($0)",
                    "\(outputPath.path)"
                ],
                inputFiles: [
                    $0,
                ],
                outputFiles: [
                    outputPath
                ]
            )
        }
    }
}
