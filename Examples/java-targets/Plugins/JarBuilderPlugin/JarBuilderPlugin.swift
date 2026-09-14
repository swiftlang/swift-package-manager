import PackagePlugin
import Foundation

@main
struct JarBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let builder = try context.tool(named: "JarBuilder")

        // TODO pull out of target and deps sources
        let classTag = URL(string: "file:/$(PRODUCTS_DIR)/JavaTarget.classes/.javaclassdir")!

        let jarFile = URL(string: "file:/$(PRODUCTS_DIR)/\(target.name).jar")!

        return [
            .buildCommand(
                displayName: "Create Jar File",
                executable: builder.url,
                arguments: [
                    "-o", jarFile.path,
                    classTag.path
                ],
                inputFiles: [classTag],
                outputFiles: [jarFile]
            ),
        ]
    }
}