import PackagePlugin
import Foundation

@main
struct JavaBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let builder = try context.tool(named: "JavaBuilder")

        guard let sourceTarget = target.sourceModule else {
            return []
        }

        let sources = sourceTarget.sourceFiles(withSuffix: ".java").map { $0.url }

        let outputDir = context.pluginWorkDirectoryURL.appending(component: "\(target.name).classes")
        let outputTag = outputDir.appending(component: ".javaclassdir")
        let productDir = URL(string: "file:/$(PRODUCTS_DIR)")!
        let productTag = productDir.appending(path: "\(target.name).classes/.javaclassdir")

        return [
            .buildCommand(
                displayName: "Java Compile",
                executable: builder.url,
                arguments: [
                    "-o", outputTag.path
                ] + sources.map { $0.path },
                inputFiles: sources,
                outputFiles: [outputTag]
            ),
            .buildCommand(
                displayName: "Copy Classes",
                executable: URL(string: "file:/$(COPY_CMD)")!,
                arguments: [
                    "-R",
                    outputDir.path,
                    productDir.path
                ],
                inputFiles: [outputTag],
                outputFiles: [productTag]
            ),
        ]
    }
}