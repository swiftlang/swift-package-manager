import Foundation

import PackagePlugin

/// The plugin that kickstarts the template executable.

@main
struct TemplatePlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let tool = try context.tool(named: "GenerateFromTemplate")
        let process = Process()

        process.executableURL = URL(filePath: tool.url.path())
        process.arguments = arguments.filter { $0 != "--" }

        try process.run()
        process.waitUntilExit()
    }
}
