import PackagePlugin
import Foundation

@main
struct JarBuilderPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let builder = try context.tool(named: "JarBuilder")

        // TODO pull out of target and deps sources
        let classTag = URL(fileURLWithPath: "/Users/dschaefer2/swift/swiftpm/work/customTargets/swift-package-manager/Examples/java-targets/.build/plugins/outputs/java-targets/JavaTarget/destination/JavaBuilderPlugin/.javaclassdir")

        let jarFile = context.pluginWorkDirectoryURL.appending(path: target.name + ".jar")

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
            )
        ]
    }
}