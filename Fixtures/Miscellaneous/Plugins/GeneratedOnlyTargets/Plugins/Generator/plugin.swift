import PackagePlugin

@main
struct Generator: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "GenerateSources")
        return target.sourceFiles.map(\.url).filter { $0.pathExtension == "ts" }.map { input in
            let outputName = target.name == "GeneratedExecutable" ? "main.swift" : "Generated.swift"
            let output = context.pluginWorkDirectoryURL.appendingPathComponent(outputName)
            return .buildCommand(
                displayName: "Generating Swift for \(target.name)",
                executable: tool.url,
                arguments: [input.path, output.path, target.name],
                inputFiles: [input],
                outputFiles: [output]
            )
        }
    }
}
