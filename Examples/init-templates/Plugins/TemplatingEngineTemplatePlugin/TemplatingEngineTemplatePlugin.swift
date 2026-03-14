import Foundation

import PackagePlugin

/// A plugin that kickstarts the TemplatingEngineTemplate executable.
@main
struct DeclarativeTemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "TemplatingEngineTemplate")
        let process = Process()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = arguments.filter { $0 != "--" }

        try process.run()
        process.waitUntilExit()
    }
}
