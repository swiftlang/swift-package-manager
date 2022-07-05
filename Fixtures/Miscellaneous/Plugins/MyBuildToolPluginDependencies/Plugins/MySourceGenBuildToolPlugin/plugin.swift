import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    // Create build commands that don't invoke the MySourceGenBuildTool source generator
    // tool directly, but instead invoke a system tool that invokes it indirectly.  We
    // want to test that we still end up with a dependency on not only that tool but also
    // on the library it depends on, even without including an explicit dependency on it.
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Build Tool Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        let inputFiles = target.sourceFiles.filter({ $0.path.extension == "dat" })
        return try inputFiles.map {
            let inputFile = $0
            let inputPath = inputFile.path
            let outputName = inputPath.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \(inputPath.lastComponent)",
                executable:
                    Path("/usr/bin/env"),
                arguments: [
                    try context.tool(named: "MySourceGenBuildTool").path,
                    "\(inputPath)",
                    "\(outputPath)"
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
