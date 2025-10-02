import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Build Tool Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        let inputFiles = target.sourceFiles.filter({ $0.path.extension == "dat" })
        let workDir = context.pluginWorkDirectoryURL

        return try inputFiles.map {
            let inputFile = $0
            let inputPath = inputFile.path
            let outputName = inputPath.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \(inputPath.lastComponent)",
                executable:
                    try context.tool(named: "mytool").path,
                arguments: [
                    "--verbose",
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
        } + [
            .prebuildCommand(
                displayName:
                    "Generating files in \(workDir.path)",
                executable:
                    try context.tool(named: "mytool").url,
                arguments:
                    ["--verbose", "\(target.directoryURL.appendingPathComponent("bar.in").path)", "\(workDir.appendingPathComponent("bar.swift").path)"],
                outputFilesDirectory: workDir
            )
        ]
    }
}
