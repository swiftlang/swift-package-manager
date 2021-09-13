import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: TargetBuildContext) throws -> [Command] {
        print("Hello from the Prebuild Plugin!")

        let outputPaths: [Path] = context.inputFiles.filter{ $0.path.extension == "dat" }.map { file in
            context.pluginWorkDirectory.appending(file.path.stem + ".swift")
        }
        var commands: [Command] = []
        if !outputPaths.isEmpty {
            commands.append(.prebuildCommand(
                displayName:
                    "Running prebuild command for target \(context.targetName)",
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
