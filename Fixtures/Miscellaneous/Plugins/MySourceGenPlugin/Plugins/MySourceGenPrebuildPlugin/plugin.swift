import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        print("Hello from the Prebuild Plugin!")
        guard let target = target as? SourceModuleTarget else { return [] }
        let outputPaths: [Path] = target.sourceFiles.filter{ $0.path.extension == "dat" }.map { file in
            context.pluginWorkDirectory.appending(file.path.stem + ".swift")
        }
        var commands: [Command] = []
        if !outputPaths.isEmpty {
            commands.append(.prebuildCommand(
                displayName:
                    "Running prebuild command for target \(target.name)",
                executable:
                    Path("/usr/bin/touch"),
                arguments: 
                    outputPaths.map{ $0.string },
                outputFilesDirectory:
                    context.pluginWorkDirectory
            ))
        }
        return commands
    }
}
