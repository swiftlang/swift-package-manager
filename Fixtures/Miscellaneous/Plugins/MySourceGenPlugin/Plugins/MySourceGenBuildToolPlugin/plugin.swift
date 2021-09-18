import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: TargetBuildContext) throws -> [Command] {
        print("Hello from the Build Tool Plugin!")

        return try context.inputFiles.map{ $0.path }.compactMap {
            guard $0.extension == "dat" else { return .none }
            let outputName = $0.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            return .buildCommand(
                displayName:
                    "Generating \(outputName) from \($0.lastComponent)",
                executable:
                    try context.tool(named: "MySourceGenBuildTool").path,
                arguments: [
                    "\($0)",
                    "\(outputPath)"
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
