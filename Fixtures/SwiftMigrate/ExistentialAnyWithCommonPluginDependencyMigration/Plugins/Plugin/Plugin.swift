import PackagePlugin
import Foundation

@main struct Plugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let tool = try context.tool(named: "Tool")
        let output = context.pluginWorkDirectory.appending(["generated.swift"])
        return [
            .buildCommand(
                displayName: "Plugin",
                executable: tool.path,
                arguments: [output],
                inputFiles: [],
                outputFiles: [output])
        ]
    }
}
