import PackagePlugin

@main
struct JavaBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let builder = try context.tool(named: "JavaBuilder")

        guard let sourceTarget = target.sourceModule else {
            return []
        }

        let sources = sourceTarget.sourceFiles.map { $0.url }

        let outputTag = context.pluginWorkDirectoryURL.appending(path: ".javaclassdir")

        return [
            .buildCommand(
                displayName: "Java Compile",
                executable: builder.url,
                arguments: [
                    "-o", outputTag.path
                ] + sources.map { $0.path },
                inputFiles: sources,
                outputFiles: [outputTag]
            )
        ]
    }
}